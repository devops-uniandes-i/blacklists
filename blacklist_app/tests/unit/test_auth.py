class TestTokenEndpoint:
    def test_valid_credentials_return_token(self, client):
        response = client.post(
            "/auth/token",
            json={"username": "admin", "password": "admin"},
        )

        assert response.status_code == 200
        body = response.get_json()
        assert "token" in body
        assert isinstance(body["token"], str)
        assert len(body["token"]) > 0

    def test_wrong_password_returns_401(self, client):
        response = client.post(
            "/auth/token",
            json={"username": "admin", "password": "wrong"},
        )

        assert response.status_code == 401
        assert "mensaje" in response.get_json()

    def test_wrong_username_returns_401(self, client):
        response = client.post(
            "/auth/token",
            json={"username": "hacker", "password": "admin"},
        )

        assert response.status_code == 401
        assert "mensaje" in response.get_json()

    def test_both_credentials_wrong_returns_401(self, client):
        response = client.post(
            "/auth/token",
            json={"username": "bad", "password": "bad"},
        )

        assert response.status_code == 401

    def test_missing_username_returns_400(self, client):
        response = client.post("/auth/token", json={"password": "admin"})

        assert response.status_code == 400

    def test_missing_password_returns_400(self, client):
        response = client.post("/auth/token", json={"username": "admin"})

        assert response.status_code == 400

    def test_empty_body_returns_400(self, client):
        response = client.post("/auth/token", json={})

        assert response.status_code == 400
