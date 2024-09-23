import os
from onelogin.saml2.auth import OneLogin_Saml2_Auth
import streamlit as st
import json

def load_saml_settings():
    with open('settings.json', 'r') as f:
        return json.load(f)

# Prepare request data without using `st.request` (Streamlit-friendly)
def prepare_saml_request():
    query_params = st.experimental_get_query_params()
    return {
        'https': 'off',  # Adjust if your app uses HTTPS
        'http_host': 'localhost',
        'server_port': '8501',
        'script_name': '/',
        'get_data': query_params,
        'post_data': {}
    }

def init_saml_auth():
    settings = load_saml_settings()
    request_data = prepare_saml_request()
    auth = OneLogin_Saml2_Auth(request_data, custom_base_path=os.getcwd())
    return auth
