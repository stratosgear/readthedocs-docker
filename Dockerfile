FROM ubuntu:16.04
MAINTAINER Stratos Gerakakis <stratosgear@gmail.com>

ENV DEBIAN_FRONTEND=noninteractive \
    APPDIR=/app \
    DJANGO_SETTINGS_MODULE=config \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    VIRTUAL_ENV=/venv \
    PATH=/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    PYTHON=/venv/bin/python \
    PIP=/venv/bin/pip \
    RTD_COMMIT=1e61c04452250d20c2fcd2d3d70dcbc7ff8cd7df
#    RTD_COMMIT=59229088f75203ac1a3077a7e49ae49f88b35ac0
# RTD_COMMIT -> Use the commit `59229088f75` - 2017-10-09
# You can change to master but this will not ensure that the docker-compose works
# https://github.com/rtfd/readthedocs.org/archive/master.zip

# Fixes an issue I had getting:
# E: Failed to fetch http://archive.ubuntu.com/ubuntu/dists/xenial-updates/main/source/by-hash/SHA256/50ccff6c903e98e2e52c1ab6dae4a85d23a84369325fd971c4bfc3752e6a7ede  Hash Sum mismatch
# E: Some index files failed to download. They have been ignored, or old ones used instead.
# Solution from: https://github.com/moby/moby/issues/30207#issuecomment-330016814
RUN touch /etc/apt/apt.conf.d/99fixbadproxy && \
  echo "Acquire::http::Pipeline-Depth 0;" >> /etc/apt/apt.conf.d/99fixbadproxy && \
  echo "Acquire::http::No-Cache true;" >> /etc/apt/apt.conf.d/99fixbadproxy && \
  echo "Acquire::BrokenProxy true;" >> /etc/apt/apt.conf.d/99fixbadproxy && \
  apt-get update -o Acquire::CompressionTypes::Order::=gz && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/* && \
  apt-get update -y

# Set locale to UTF-8
RUN apt-get clean && apt-get update && apt-get install -y locales && \
    locale-gen en_US.UTF-8 && \
    update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
    

# Update python
RUN apt-get -qq update && \
    apt-get -y -qq upgrade && \
    apt-get install -y -qq \
        python libxml2-dev libxslt1-dev expat libevent-dev wget python-dev \
        texlive texlive-latex-extra language-pack-en unzip git python-pip \
        zlib1g-dev lib32z1-dev libpq-dev gettext curl nginx sqlite3 && \
    apt-get clean

# Install test dependencies
RUN pip install -q \
    virtualenv \
    supervisor

# Setting up virtualenv
RUN virtualenv /venv

# Add user py
RUN adduser --gecos 'py' --disabled-password py

RUN mkdir -p $APPDIR
WORKDIR $APPDIR

# Setup read the doc

## Extract readthedocs
RUN wget -q --no-check-certificate -O /tmp/master.zip \
        https://github.com/rtfd/readthedocs.org/archive/$RTD_COMMIT.zip && \
    unzip /tmp/master.zip >/dev/null 2>/dev/null && \
    mv readthedocs.org-$RTD_COMMIT/* readthedocs.org-$RTD_COMMIT/.??* . && \
    rmdir readthedocs.org-$RTD_COMMIT && \
    rm /tmp/master.zip && \
    $PIP install -U \
        --allow-external bzr --allow-unverified bzr \
        -r $APPDIR/requirements.txt && \
    $PIP install psycopg2 && \
    $PIP install git+https://github.com/rtfd/readthedocs-sphinx-ext.git

COPY files /

RUN $PYTHON setup.py develop

## Copy special configuration for read the docs
RUN ln -s "$APPDIR/readthedocs/static/vendor" "$APPDIR/readthedocs/core/static/vendor" && \
    ln -s $APPDIR/manage.py $APPDIR/readthedocs/manage.py && \
    ln -s $APPDIR/readthedocs/core/static $APPDIR/media/ && \
    ln -s $APPDIR/readthedocs/builds/static/builds $APPDIR/media/static/builds && \
    ln -s /etc/nginx/sites-available/readthedocs /etc/nginx/sites-enabled/readthedocs && \
    rm /etc/nginx/sites-enabled/default && \
    mkdir -p $APPDIR/prod_artifacts/media && \
    chmod +x $APPDIR/bin/* && \
    chown -R py .

# Build RTD's locale files
RUN cd $APPDIR/readthedocs && \
    $PYTHON manage.py makemessages --all && \
    $PYTHON manage.py compilemessages


# Docker config
EXPOSE 80
VOLUME [ "/app" ]

CMD [ "supervisord", "-c", "/etc/supervisord.conf", "-n" ]
