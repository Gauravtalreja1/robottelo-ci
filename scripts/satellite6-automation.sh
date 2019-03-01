pip install -U -r requirements.txt docker-py pytest-xdist==1.25.0 sauceclient pytest-timeout

cp config/robottelo.properties ./robottelo.properties

sed -i "s/{server_hostname}/${SERVER_HOSTNAME}/" robottelo.properties
sed -i "s|# screenshots_path=.*|screenshots_path=$(pwd)/screenshots|" robottelo.properties
sed -i "s|external_url=.*|external_url=http://${SERVER_HOSTNAME}:2375|" robottelo.properties

# Robottelo logging configuration
sed -i "s/'\(robottelo\).log'/'\1-${ENDPOINT}.log'/" logging.conf

# Sauce Labs Configuration and pytest-env setting.
if [[ "${SATELLITE_VERSION}" == "6.4" || "${SATELLITE_VERSION}" == "6.5" ]]; then
    SAUCE_BROWSER="chrome"

    pip install -U pytest-env

    env =
        PYTHONHASHSEED=0
fi

if [[ "${SAUCE_PLATFORM}" != "no_saucelabs" ]]; then
    echo "The Sauce Tunnel Identifier for Server Hostname ${SERVER_HOSTNAME} is ${TUNNEL_IDENTIFIER}"
    sed -i "s/^browser.*/browser=saucelabs/" robottelo.properties
    sed -i "s/^# saucelabs_user=.*/saucelabs_user=${SAUCELABS_USER}/" robottelo.properties
    sed -i "s/^# saucelabs_key=.*/saucelabs_key=${SAUCELABS_KEY}/" robottelo.properties
    sed -i "s/^# webdriver=.*/webdriver=${SAUCE_BROWSER}/" robottelo.properties
    if [[ "${SAUCE_BROWSER}" == "firefox" ]]; then
        # Temporary change to test Selenium and Firefox changes.
        if [[ "${SATELLITE_VERSION}" == "6.1" ]]; then
            BROWSER_VERSION=45.0
        else
            BROWSER_VERSION=47.0
        fi
    elif [[ "${SAUCE_BROWSER}" == "edge" ]]; then
        BROWSER_VERSION=14.14393
    elif [[ "${SAUCE_BROWSER}" == "chrome" ]]; then
        BROWSER_VERSION=63.0
    fi
    # Temporary change to test Selenium and Firefox changes.
    if [[ "${SATELLITE_VERSION}" == "6.1" ]]; then
        SELENIUM_VERSION=2.48.0
    elif [[ "${SATELLITE_VERSION}" == "6.2" || "${SATELLITE_VERSION}" == "6.3" ]]; then
        SELENIUM_VERSION=2.53.1
    else
        SELENIUM_VERSION=3.14.0
    fi
    sed -i "s/^# webdriver_desired_capabilities=.*/webdriver_desired_capabilities=platform=${SAUCE_PLATFORM},version=${BROWSER_VERSION},maxDuration=5400,idleTimeout=1000,seleniumVersion=${SELENIUM_VERSION},build=${BUILD_LABEL},screenResolution=1600x1200,tunnelIdentifier=${TUNNEL_IDENTIFIER},extendedDebugging=true,tags=[${JOB_NAME}]/" robottelo.properties
fi

# Bugzilla Login Details

sed -i "s/# bz_password=.*/bz_password=${BUGZILLA_PASSWORD}/" robottelo.properties
sed -i "s/# bz_username=.*/bz_username=${BUGZILLA_USER}/" robottelo.properties

# AWS Access Keys Configuration

sed -i "s/# access_key=.*/access_key=${AWS_ACCESSKEY_ID}/" robottelo.properties
sed -i "s|# secret_key=.*|secret_key=${AWS_ACCESSKEY_SECRET}|" robottelo.properties

# Robottelo Capsule Configuration

sed -i "s/^# \[capsule\].*/[capsule]/" robottelo.properties
sed -i "s/^# instance_name=.*/instance_name=${SERVER_HOSTNAME%%.*}-capsule/" robottelo.properties
sed -i "s/^# domain=.*/domain=${DDNS_DOMAIN}/" robottelo.properties
sed -i "s/^# hash=.*/hash=${CAPSULE_DDNS_HASH}/" robottelo.properties
sed -i "s|^# ddns_package_url=.*|ddns_package_url=${DDNS_PACKAGE_URL}|" robottelo.properties

if [ -n "${IMAGE}" ]; then
    sed -i "s/^# \[distro\].*/[distro]/" robottelo.properties
    sed -i "s/^# image_el6=.*/image_el6=${IMAGE}/" robottelo.properties
    sed -i "s/^# image_el7=.*/image_el7=${IMAGE}/" robottelo.properties
fi

# upstream = 1 for Distributions: UPSTREAM (default in robottelo.properties)
# upstream = 0 for Distributions: DOWNSTREAM, CDN, BETA, ISO
if [[ "${SATELLITE_VERSION}" != *"upstream-nightly"* ]]; then
   sed -i "s/^upstream=.*/upstream=false/" robottelo.properties
   sed -i "s/^# \[vlan_networking\].*/[vlan_networking]/" robottelo.properties
   sed -i "s/^# subnet=.*/subnet=${SUBNET}/" robottelo.properties
   sed -i "s/^# netmask=.*/netmask=${NETMASK}/" robottelo.properties
   sed -i "s/^# gateway=.*/gateway=${GATEWAY}/" robottelo.properties
   sed -i "s/^# bridge=.*/bridge=${BRIDGE}/" robottelo.properties
   # To set the discovery ISO name in properties file
   sed -i "s/^# \[discovery\].*/[discovery]/" robottelo.properties
   sed -i "s/^# discovery_iso=.*/discovery_iso=${DISCOVERY_ISO}/" robottelo.properties
fi

# cdn = 1 for Distributions: GA (default in robottelo.properties)
# cdn = 0 for Distributions: INTERNAL, BETA, ISO
# Sync content and use the below repos only when DISTRIBUTION is not GA
if [[ "${SATELLITE_DISTRIBUTION}" != *"GA"* ]]; then
    # The below cdn flag is required by automation to flip between RH & custom syncs.
    sed -i "s/^cdn=.*/cdn=false/" robottelo.properties
    # Usage of '|' is intentional as TOOLS_REPO can bring in http url which has '/'
    sed -i "s|sattools_repo=.*|sattools_repo=rhel7=${RHEL7_TOOLS_REPO},rhel6=${RHEL6_TOOLS_REPO}|" robottelo.properties
    sed -i "s|capsule_repo=.*|capsule_repo=${CAPSULE_REPO}|" robottelo.properties
fi


if [[ "${SATELLITE_VERSION}" == "6.2" || "${SATELLITE_VERSION}" == "6.3" ]]; then
    TEST_TYPE="$(echo tests/foreman/{api,cli,ui,longrun,sys,installer})"
elif [[ "${SATELLITE_VERSION}" == "6.1" ]]; then
    TEST_TYPE="$(echo tests/foreman/{api,cli,ui,longrun})"
else
    TIMEOUT="$(echo --timeout 7000 --timeout-method=thread)"
    if [[ "${ENDPOINT}" == "tier2" ]]; then
        TEST_TYPE="$(echo tests/foreman/{ui_airgun,api,cli,longrun,sys,installer})"
    elif [[ "${ENDPOINT}" == "tier3" ]]; then
        TEST_TYPE="$(echo tests/foreman/{api,cli,ui_airgun,longrun,sys,installer})"
    else
        TEST_TYPE="$(echo tests/foreman/{api,cli,longrun,sys,installer,ui_airgun})"
    fi
fi

if [ "${ENDPOINT}" == "destructive" ]; then
    make test-foreman-sys
elif [ "${ENDPOINT}" != "rhai" ]; then
    set +e
    # Run sequential tests
    $(which py.test) -v --junit-xml="${ENDPOINT}-sequential-results.xml" \
        -o junit_suite_name="${ENDPOINT}-sequential" \
        -m "${ENDPOINT} and run_in_one_thread and not stubbed" \
        ${TEST_TYPE} ${TIMEOUT}

    # Run parallel tests
    $(which py.test) -v --junit-xml="${ENDPOINT}-parallel-results.xml" -n "${ROBOTTELO_WORKERS}" \
        -o junit_suite_name="${ENDPOINT}-parallel" \
        -m "${ENDPOINT} and not run_in_one_thread and not stubbed" \
        ${TEST_TYPE} ${TIMEOUT}
    set -e
else
    make test-foreman-${ENDPOINT} PYTEST_XDIST_NUMPROCESSES=${ROBOTTELO_WORKERS}
fi

if [ "${ROBOTTELO_WORKERS}" -gt 0 ]; then
    make logs-join
    make logs-clean
fi

echo
echo "========================================"
echo "Server information"
echo "========================================"
echo "Hostname: ${SERVER_HOSTNAME}"
echo "Credentials: admin/changeme"
echo "========================================"
echo
echo "========================================"
