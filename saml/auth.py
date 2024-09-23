from onelogin.saml2.auth import OneLogin_Saml2_Auth
from flask import request

def init_saml_auth(req):
    auth = OneLogin_Saml2_Auth(req, custom_base_path='/path/to/saml/config/')
    return auth

def prepare_flask_request(request):
    url_data = urlparse(request.url)
    return {
        'https': 'on' if request.scheme == 'https' else 'off',
        'http_host': request.host,
        'server_port': url_data.port,
        'script_name': request.path,
        'get_data': request.args.copy(),
        'post_data': request.form.copy(),
    }
