import streamlit as st
from keycloak import KeycloakOpenID
import requests

# Keycloak configuration
keycloak_openid = KeycloakOpenID(server_url="http://localhost:8080/",
                                 client_id="application_2",
                                 realm_name="peri-nimble-poc",
                                 client_secret_key="iHcl858m4EuIqXJUhOMVjZNjwDhDh6On")

# Authentication URL
auth_url = keycloak_openid.auth_url(redirect_uri="http://localhost:8502")

# Set page configuration
st.set_page_config(page_title="Peri-Nimble PoC: App_2", page_icon=":key:", layout="centered")

# Custom CSS for styling
st.markdown("""
    <style>
    .main {
        border-radius: 10px;
        padding: 20px;
    }
    .stButton button {
        background-color: #4CAF50;
        color: white;
        font-weight: bold;
    }
    </style>
    """, unsafe_allow_html=True)

# Application title
st.title("Welcome to Peri-Nimble PoC")

# Check for authentication token
if "token" not in st.session_state:
    if "code" in st.query_params:
        token = keycloak_openid.token(grant_type="authorization_code",
                                      code=st.query_params["code"],
                                      redirect_uri="http://localhost:8502")
        st.session_state["token"] = token
        st.experimental_rerun()
    else:
        st.info("Please log in to continue.")
        st.markdown(f"[Login]({auth_url})", unsafe_allow_html=True)
else:
    # Display the session state
    st.markdown("Application 2: User Session Information")

    user = st.session_state["token"]
    # st.write(user["access_token"])
    print(st.write("**Session State:**", user["session_state"]))

