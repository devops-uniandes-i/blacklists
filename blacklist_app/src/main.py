import os
import re
import uuid
from datetime import datetime, timezone
from flask import Flask, jsonify, request
from flask_jwt_extended import create_access_token, jwt_required
from flask_restful import Api, Resource
from marshmallow import ValidationError, fields, validate

import src.models as models
from src.database import db, jwt, ma

app = Flask(__name__)
api = Api(app)
app.config["PROPAGATE_EXCEPTIONS"] = True

app.config["SQLALCHEMY_DATABASE_URI"] = os.getenv(
    "DATABASE_URL",
    "postgresql://postgres:postgres@blacklist-db:5432/blacklist-db",
)
app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False
app.config["JWT_SECRET_KEY"] = os.getenv("JWT_SECRET_KEY", "change-this-secret")

db.init_app(app)
ma.init_app(app)
jwt.init_app(app)


@jwt.unauthorized_loader
def jwt_missing_token(reason):
    return jsonify({"mensaje": "Token no enviado o formato Bearer invalido", "detail": reason}), 401


@jwt.invalid_token_loader
def jwt_invalid_token(reason):
    return jsonify({"mensaje": "Token invalido", "detail": reason}), 401


@jwt.expired_token_loader
def jwt_expired_token(_jwt_header, _jwt_payload):
    return jsonify({"mensaje": "Token expirado"}), 401


@jwt.revoked_token_loader
def jwt_revoked_token(_jwt_header, _jwt_payload):
    return jsonify({"mensaje": "Token revocado"}), 401


if os.getenv("ENV") != "test":
    with app.app_context():
        db.create_all()


class BlacklistInputSchema(ma.Schema):
    email = fields.Email(required=True)
    app_uuid = fields.String(required=True)
    blocked_reason = fields.String(required=False, allow_none=True, validate=validate.Length(max=255))


class TokenInputSchema(ma.Schema):
    username = fields.String(required=True)
    password = fields.String(required=True)


class BlacklistOutputSchema(ma.Schema):
    id = fields.String()
    email = fields.Email()
    app_uuid = fields.String()
    blocked_reason = fields.String(allow_none=True)
    ip_address = fields.String()
    created_at = fields.DateTime()


blacklist_input_schema = BlacklistInputSchema()
blacklist_output_schema = BlacklistOutputSchema()
token_input_schema = TokenInputSchema()


def _is_valid_uuid(value: str) -> bool:
    try:
        uuid.UUID(value)
    except ValueError:
        return False
    return True


def _request_ip() -> str:
    forwarded_for = request.headers.get("X-Forwarded-For")
    if forwarded_for:
        return forwarded_for.split(",")[0].strip()
    return request.remote_addr or "unknown"


class RootResource(Resource):
    def get(self):
        return {"Hello": "World"}, 200


class HealthResource(Resource):
    def get(self):
        return "pong", 200


class TokenResource(Resource):
    def post(self):
        payload = request.get_json(silent=True) or {}
        data = token_input_schema.load(payload)

        expected_user = os.getenv("AUTH_USERNAME", "admin")
        expected_password = os.getenv("AUTH_PASSWORD", "admin")
        if data["username"] != expected_user or data["password"] != expected_password:
            return {"mensaje": "Credenciales inválidas"}, 401

        token = create_access_token(identity=data["username"])
        return {"token": token}, 200


class BlacklistResource(Resource):
    @jwt_required()
    def get(self, email=None):
        if email is None:
            email = (request.args.get("email") or "").strip().lower()
        if not email or not bool(re.match(r"^[^@\s]+@[^@\s]+\.[^@\s]+$", email)):
            return {"mensaje": "El parámetro email es obligatorio y debe ser válido"}, 400

        entry = models.Blacklist.query.filter_by(email=email).first()
        if not entry:
            return {"is_blacklisted": False, "email": email}, 404

        return {
            "is_blacklisted": True,
            "email": entry.email,
            "reason": entry.blocked_reason,
        }, 200


    @jwt_required()
    def post(self):
        payload = request.get_json(silent=True) or {}

        missing_fields = []
        if not str(payload.get("email", "")).strip():
            missing_fields.append("email")
        if not str(payload.get("app_uuid", "")).strip():
            missing_fields.append("app_uuid")

        if missing_fields:
            return {
                "mensaje": "Faltan campos obligatorios",
                "errors": {field: ["Missing data for required field."] for field in missing_fields},
            }, 400

        data = blacklist_input_schema.load(payload)

        email = data["email"].strip().lower()
        app_uuid = data["app_uuid"].strip()
        blocked_reason = data.get("blocked_reason")

        if not _is_valid_uuid(app_uuid):
            return {"mensaje": "El campo app_uuid es obligatorio y debe ser un UUID válido"}, 400

        exists = models.Blacklist.query.filter_by(email=email).first()
        if exists:
            return {"mensaje": "El email ya se encuentra en la lista negra"}, 412

        entry = models.Blacklist(
            id=str(uuid.uuid4()),
            email=email,
            app_uuid=app_uuid,
            blocked_reason=blocked_reason,
            ip_address=_request_ip(),
            created_at=datetime.now(timezone.utc),
        )
        db.session.add(entry)
        db.session.commit()

        return blacklist_output_schema.dump(entry), 201


@app.errorhandler(ValidationError)
def marshmallow_validation_handler(err):
    return jsonify({"mensaje": "Solicitud invalida", "errors": err.messages}), 400


api.add_resource(RootResource, "/")
api.add_resource(HealthResource, "/health")
api.add_resource(TokenResource, "/auth/token")
api.add_resource(BlacklistResource, "/blacklists", "/blacklists/<string:email>")


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "3012")))
