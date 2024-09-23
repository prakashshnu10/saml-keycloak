import streamlit as st
from keycloak import KeycloakOpenID
from keycloak.exceptions import KeycloakAuthenticationError
import requests

# Keycloak configuration
KEYCLOAK_SERVER_URL = "http://localhost:8080/"
KEYCLOAK_REALM = "peri-nimble-poc"
KEYCLOAK_CLIENT_ID = "periNimble-app"
KEYCLOAK_CLIENT_SECRET = "TXLmPgugfB2CxidPMwIqub41tlMLWeyn"

# Initialize Keycloak client
keycloak_openid = KeycloakOpenID(
    server_url=KEYCLOAK_SERVER_URL,
    client_id=KEYCLOAK_CLIENT_ID,
    realm_name=KEYCLOAK_REALM,
    client_secret_key=KEYCLOAK_CLIENT_SECRET
)

# User login and token validation functions
def login_user(username, password):
    try:
        token = keycloak_openid.token(username, password, "password")
        return token["access_token"]
    except KeycloakAuthenticationError as e:
        st.error(f"Invalid credentials: {str(e)}")
        return None

def validate_token(token):
    try:
        userinfo = keycloak_openid.userinfo(token)
         # Add roles to the userinfo
        # roles = userinfo.get('roles', [])
        # print(userinfo)
        return userinfo
    except Exception as e:
        st.error(f"Error validating token: {str(e)}")
        return None

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

# Streamlit UI
st.title("PeriNimble-NU10: KeyCloak PoC")
st.markdown("On Authentication & Authorization PoC")


# Login form
if "token" not in st.session_state:
    username = st.text_input("Username")
    password = st.text_input("Password", type="password")
    
    if st.button("Login"):
        token = login_user(username, password)
        if token:
            st.session_state["token"] = token
            st.experimental_rerun()

def check_role(roles, role_to_check):
    return role_to_check in roles

# After login
if "token" in st.session_state:
    userinfo = validate_token(st.session_state["token"])
    
    if userinfo:
        role = userinfo["resource_access"]["periNimble-app"]["roles"]
        print(role)
        
        # RBAC - Display content based on roles
        if check_role(role, "finance"):
            st.subheader("Finance Dashboard")
            st.write("This is the Finance page, accessible only by users with the Finance role.")
        elif check_role(role, "marketing"):
            st.subheader("Marketing Dashboard")
            st.write("This is the Marketing page, accessible only by users with the Marketing role.")
        else:
            st.write("You do not have access to any pages.")

        # Logout button
        if st.button("Logout"):
            del st.session_state["token"]
            st.experimental_rerun()

else:
    st.write("Please log in to access the content.")
