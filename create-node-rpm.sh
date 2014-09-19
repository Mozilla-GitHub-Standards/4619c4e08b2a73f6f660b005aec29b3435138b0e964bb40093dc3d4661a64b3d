#!/bin/sh
# vim: ft=sh

cd $(dirname $0)
BASE=$(pwd)
BUILD_DIR=$BASE/BUILD

DIST_VERSION=$(/usr/lib/rpm/redhat/dist.sh --el)

if [ $# -eq 2 ]; then
    DIST_VERSION=$2
fi

# how this script works: 
#
# 1. it will copy the spec file to the build directory
# 2. it will create an SRPM for mock
# 3. it will build the RPM using mock
# 4. done

function logmsg { echo "$(date '+%Y %m %d %H:%M:%S') $@"; }
function logerr { echo "$@" >&2; }

function sanityCheck
{

    SPEC_FILE="node-v$1.spec"
    if [ ! -e $BASE/specs/$SPEC_FILE ]; then
        logerr "ERROR: spec file specs/$SPEC_FILE does not exist"
        logerr "Available Versions: "
        for V in $(ls -1 specs/node*.spec | sed -r 's/^.*-v(.*).spec$/\1/');
        do
            logerr "  - $V"
        done
        exit 1
    fi

    if [ -z $(command -v mock) ]; then
        logerr "ERROR: mock command not found"
        exit 1
    fi

    groups | grep -qi mock
    if [ $? != 0 ]; then
        logerr "ERROR: Not part of the mock group"
        exit 1
    fi
}

function buildSRPM
{
    VERSION="$1"
    PACKAGE_NAME="nodejs-svcops-$VERSION-1.el${DIST_VERSION}.src.rpm"
    SPEC_FILE="$BASE/specs/node-v$VERSION.spec"

    if [ ! -e $BUILD_DIR/SRPMS/$PACKAGE_NAME ]; then

        for d in SOURCES SPECS RPMS SRPMS
        do
            if [ ! -e $BUILD_DIR/$d ]; then
                mkdir -p $BUILD_DIR/$d
            fi
        done

        cp $SPEC_FILE $BUILD_DIR/SPECS
        cp $BASE/specs/*.patch $BUILD_DIR/SOURCES

        SRC_ARCHIVE="http://nodejs.org/dist/v${VERSION}/node-v${VERSION}.tar.gz"
        logmsg "Fetching $SRC_ARCHIVE"
        OUTFILE="$BUILD_DIR/SOURCES/node-v${VERSION}.tar.gz"
        if [ ! -e $OUTFILE ]; then
            curl --silent --fail "$SRC_ARCHIVE" -o $OUTFILE
        fi

        CHECK=$(curl --silent --fail http://nodejs.org/dist/v$VERSION/SHASUMS.txt | awk "/node-v$VERSION.tar.gz/ {print \$1}")

        OUTSHA=$(sha1sum $OUTFILE | awk '{print $1}')

        if [ $CHECK != $OUTSHA ]; then
            logerr "SHA1 on $OUTFILE did not match, EXPECTED=$CHECK, GOT=$OUTSHA"
            exit 1
        else
            logmsg "Download OK. SHA1 sums match: $CHECK"
        fi

        if [ $? -gt 0 ]; then
            logerr "ERROR: Failed to fetch $SRC_ARCHIVE"
            exit 1
        fi

        logmsg "Building SRPM"

        mock --quiet \
            --buildsrpm \
            --root epel-${DIST_VERSION}-x86_64 \
            --spec $BUILD_DIR/SPECS/node-v$VERSION.spec \
            --sources $BUILD_DIR/SOURCES \
            --resultdir $BUILD_DIR/SRPMS

        if [ $? -gt 0 ]; then
            logerr "Mock build error"
            exit 1
        fi
    else
        logmsg "$PACKAGE_NAME already exists... skipping SRPM build"
    fi
}

function buildRPM
{
    logmsg "Building Node.js RPM"
    mock --quiet \
        --root epel-${DIST_VERSION}-x86_64 \
        --resultdir $BUILD_DIR/RPMS \
        $BUILD_DIR/SRPMS/$PACKAGE_NAME
}

if [ $# -lt 1 ]; then
    logerr "Usage: $0 <version> <rhel version - defaults to system>"
    logerr "  example, $0 0.10.21    - default to release version of system"
    logerr "  example, $0 0.10.32 6  - for EPEL6"
    logerr "  example, $0 0.10.32 7  - for EPEL7"
    exit 1
fi

VERSION=$1

logmsg "Building for RHEL $DIST_VERSION"
sanityCheck $VERSION
buildSRPM $VERSION
buildRPM
