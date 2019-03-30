VERSION=0.2.0

# PHP SAPI list, default is cli only.
PHP_SAPI_LIST="${PHP_SAPI_LIST:=cli}"

SOFTWARE_INSTALL_ROOT=${SOFTWARE_INSTALL_ROOT:=~/opt}

# Colorize provisioning.
COLOR_SECTION='\e[94m'
COLOR_NOTICE='\e[32m'
COLOR_ERROR='\e[91m'

MENU_BACKTITLE="Perch Labs Setupifier Menu v${VERSION}"
