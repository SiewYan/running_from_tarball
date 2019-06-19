#!/bin/bash

export X509_USER_PROXY=/homeui/hoh/x509up_u761
export HOME=${PWD}

tar xvaf submit.tgz
cd submit
. runEventGeneration.sh
cd ${HOME}
rm -r submit/

exit 0
