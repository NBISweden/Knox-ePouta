#!/bin/bash

if [ -z $OS_USERNAME_EPOUTA ]; then
    echo "ERROR: No username found, for ePouta, in [$ABOVE/user.rc]"
    echo "Exiting..."
    exit 1;
fi


unset OS_ENDPOINT_TYPE
unset OS_PROJECT_DOMAIN_ID
unset OS_USER_DOMAIN_ID
unset OS_IMAGE_API_VERSION

# To use an Openstack cloud you need to authenticate against keystone, which
# returns a **Token** and **Service Catalog**.  The catalog contains the
# endpoint for all services the user/tenant has access to - including nova,
# glance, keystone, swift.
#
# *NOTE*: Using the 2.0 *auth api* does not mean that compute api is 2.0.  We
# will use the 1.1 *compute api*
export OS_AUTH_URL=https://epouta.csc.fi:5001/v3

# Use keystone v3 api
export OS_IDENTITY_API_VERSION=3

# Specify the domain for the v3 api
export OS_USER_DOMAIN_NAME=users

# With the addition of Keystone we have standardized on the term **tenant**
# as the entity that owns the resources.
export OS_TENANT_ID=f046b6a3777640fd9572ea2ffe5131eb
export OS_PROJECT_NAME="Project_2000039"
export OS_TENANT_NAME=$OS_PROJECT_NAME

# In addition to the owning entity (tenant), openstack stores the entity
# performing the action as the **user**.
export OS_USERNAME=$OS_USERNAME_EPOUTA

# With Keystone you pass the keystone password.
echo "Please enter your OpenStack Password: "
read -sr OS_PASSWORD_INPUT
export OS_PASSWORD=$OS_PASSWORD_INPUT

# If your configuration has multiple regions, we set that information here.
# OS_REGION_NAME is optional and only valid in certain environments.
export OS_REGION_NAME="esp-prod"
# Don't leave a blank variable, unset it if it was empty
if [ -z "$OS_REGION_NAME" ]; then unset OS_REGION_NAME; fi
