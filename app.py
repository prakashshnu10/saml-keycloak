from flask import Flask, redirect, request, session
from onelogin.saml2.auth import OneLogin_Saml2_Auth
import os

app = Flask(__name__)
app.secret_key = os.urandom(24)


def init_saml_auth(req):
    auth = OneLogin_Saml2_Auth(req, custom_base_path=os.path.join(os.getcwd(), 'saml'))
    return auth


def prepare_flask_request(request):
    url_data = request.url
    return {
        'https': 'on' if request.scheme == 'https' else 'off',
        'http_host': request.host,
        'server_port': request.host.split(':')[1] if ':' in request.host else '80',
        'script_name': request.path,
        'get_data': request.args.copy(),
        'post_data': request.form.copy()
    }


@app.route('/')
def index():
    return 'Welcome to the SAML Authentication PoC!'


@app.route('/login')
def login():
    req = prepare_flask_request(request)
    auth = init_saml_auth(req)
    return redirect(auth.login())


@app.route('/saml/acs', methods=['POST'])
def saml_acs():
    req = prepare_flask_request(request)
    auth = init_saml_auth(req)
    auth.process_response()
    errors = auth.get_errors()

    if len(errors) == 0:
        if auth.is_authenticated():
            session['user_data'] = auth.get_attributes()
            return redirect('/dashboard')
    return 'Error in SAML Authentication: ' + ', '.join(errors)


@app.route('/dashboard')
def dashboard():
    if 'user_data' in session:
        return f'Hello, {session["user_data"]["email"][0]}!'
    return redirect('/')


if __name__ == '__main__':
    app.run(debug=True)
