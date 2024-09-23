import streamlit as st
from onelogin.saml2.auth import OneLogin_Saml2_Auth
from onelogin.saml2.settings import OneLogin_Saml2_Settings
import os
from flask import Flask, request, redirect, make_response
from urllib.parse import urlparse  # Correct import

app = Flask(__name__)

def init_saml_auth(req):
    auth = OneLogin_Saml2_Auth(req, custom_base_path=os.path.dirname(__file__))
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
        'query_string': request.query_string
    }

@app.route('/sso/saml', methods=['POST', 'GET'])
def sso_saml():
    req = prepare_flask_request(request)
    auth = init_saml_auth(req)
    errors = auth.process_response()
    if not auth.is_authenticated():
        return redirect(auth.login())
    session['samlUserdata'] = auth.get_attributes()
    session['samlNameId'] = auth.get_nameid()
    session['samlSessionIndex'] = auth.get_session_index()
    return redirect('/')

@app.route('/sso/metadata')
def metadata():
    saml_settings = OneLogin_Saml2_Settings(settings=None, custom_base_path=os.path.dirname(__file__))
    metadata = saml_settings.get_sp_metadata()
    errors = saml_settings.validate_metadata(metadata)
    if len(errors) == 0:
        response = make_response(metadata, 200)
        response.headers['Content-Type'] = 'text/xml'
    else:
        response = make_response(', '.join(errors), 500)
    return response

if __name__ == '__main__':
    app.run(debug=True)

# Streamlit UI
st.title("Keycloak SSO with SAML in Streamlit")

if 'samlUserdata' in session:
    st.write(f"Hello, {session['samlUserdata']['email'][0]}")
    st.write("SAML User Attributes:")
    st.json(session['samlUserdata'])
else:
    st.write("You are not logged in.")
    if st.button("Login"):
        st.write("Redirecting to Keycloak...")
        redirect_url = "http://localhost:5000/sso/saml"
        st.experimental_rerun()
