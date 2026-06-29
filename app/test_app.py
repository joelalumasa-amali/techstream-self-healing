import pytest
from unittest.mock import patch, MagicMock
from app import app as flask_app


@pytest.fixture
def client():
    flask_app.config['TESTING'] = True
    with flask_app.test_client() as c:
        yield c


def test_home_returns_ok(client):
    with patch('app.put_metric'):
        response = client.get('/')
    assert response.status_code == 200
    data = response.get_json()
    assert data['status'] == 'ok'
    assert data['service'] == 'TechStream'


def test_health_returns_healthy(client):
    response = client.get('/health')
    assert response.status_code == 200
    assert response.get_json()['healthy'] is True


def test_error_returns_500(client):
    with patch('app.put_metric'):
        response = client.get('/error')
    assert response.status_code == 500
    assert 'error' in response.get_json()


def test_chaos_returns_500(client):
    with patch('app.put_metric'), patch('app.os.system') as mock_sys:
        response = client.get('/chaos')
        mock_sys.assert_called_once_with('stress-ng --cpu 1 --timeout 10s &')
    assert response.status_code == 500
    assert 'chaos' in response.get_json()


def test_restart_endpoint_removed(client):
    response = client.get('/restart')
    assert response.status_code == 404


def test_home_emits_metrics(client):
    with patch('app.put_metric') as mock_metric:
        client.get('/')
    calls = [c.args[0] for c in mock_metric.call_args_list]
    assert 'RequestCount' in calls
    assert 'Latency' in calls


def test_put_metric_swallows_exceptions():
    with patch('app.get_cloudwatch') as mock_cw:
        mock_cw.return_value = MagicMock(
            put_metric_data=MagicMock(side_effect=Exception('AWS error'))
        )
        from app import put_metric
        put_metric('TestMetric', 1)
