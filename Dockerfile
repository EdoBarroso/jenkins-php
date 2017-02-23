# Jenkins + PHP, following some of the steps available at https://modess.io/jenkins-php/, but taking the Official Docker Jenkins Dockerfile as base
FROM openjdk:8-jdk

MAINTAINER Eduardo Barroso <ebarroso@gmail.com>

# I'm adding the Dotdeb repo for the latest version of the PHP packages
RUN echo 'deb http://packages.dotdeb.org jessie all' >> /etc/apt/sources.list
RUN wget https://www.dotdeb.org/dotdeb.gpg; \
	apt-key add dotdeb.gpg; \
	rm dotdeb.gpg

# Upgrade the system to the latest version, then install GIT, 
# curl and some PHP 7.0 packages
RUN apt-get update && apt-get upgrade -y
RUN apt-get install -y git curl php7.0 php7.0-xdebug php7.0-xsl php7.0-dom php7.0-zip php7.0-mbstring && rm -rf /var/lib/apt/lists/*

ENV JENKINS_HOME /var/jenkins_home
ENV JENKINS_SLAVE_AGENT_PORT 50000

ARG user=jenkins
ARG group=jenkins
ARG uid=1000
ARG gid=1000

# Jenkins is run with user `jenkins`, uid = 1000
# If you bind mount a volume from the host or a data container, 
# ensure you use the same uid
RUN groupadd -g ${gid} ${group} \
    && useradd -d "$JENKINS_HOME" -u ${uid} -g ${gid} -m -s /bin/bash ${user}

# Jenkins home directory is a volume, so configuration and build history 
# can be persisted and survive image upgrades
VOLUME /var/jenkins_home

# `/usr/share/jenkins/ref/` contains all reference configuration we want 
# to set on a fresh new installation. Use it to bundle additional plugins 
# or config file with your custom jenkins Docker image.
RUN mkdir -p /usr/share/jenkins/ref/init.groovy.d

ENV TINI_VERSION 0.13.2
ENV TINI_SHA afbf8de8a63ce8e4f18cb3f34dfdbbd354af68a1

# Use tini as subreaper in Docker container to adopt zombie processes 
RUN curl -fsSL https://github.com/krallin/tini/releases/download/v${TINI_VERSION}/tini-static-amd64 -o /bin/tini && chmod +x /bin/tini \
  && echo "$TINI_SHA  /bin/tini" | sha1sum -c -

COPY init.groovy /usr/share/jenkins/ref/init.groovy.d/tcp-slave-agent-port.groovy

# Install latest version of Composer
RUN php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"; \
	php -r "if (hash_file('SHA384', 'composer-setup.php') === '55d6ead61b29c7bdee5cccfb50076874187bd9f21f65d8991d46ec5cc90518f447387fb9f76ebae1fbbacf329e583e30') { echo 'Installer verified'; } else { echo 'Installer corrupt'; unlink('composer-setup.php'); } echo PHP_EOL;"; \
	php composer-setup.php --install-dir=/usr/local/bin --filename=composer; \
	php -r "unlink('composer-setup.php');"; \
	chown -R ${user} ~/.composer/

# jenkins version being bundled in this docker image
ARG JENKINS_VERSION
ENV JENKINS_VERSION ${JENKINS_VERSION:-2.32.2}

# jenkins.war checksum, download will be validated using it
ARG JENKINS_SHA=f495a08733f69b1845fd2d9b3a46482adb6e6cee

# Can be used to customize where jenkins.war get downloaded from
ARG JENKINS_URL=https://repo.jenkins-ci.org/public/org/jenkins-ci/main/jenkins-war/${JENKINS_VERSION}/jenkins-war-${JENKINS_VERSION}.war

# could use ADD but this one does not check Last-Modified header neither does it allow to control checksum 
# see https://github.com/docker/docker/issues/8331
RUN curl -fsSL ${JENKINS_URL} -o /usr/share/jenkins/jenkins.war \
  && echo "${JENKINS_SHA}  /usr/share/jenkins/jenkins.war" | sha1sum -c -

ENV JENKINS_UC https://updates.jenkins.io
RUN chown -R ${user} "$JENKINS_HOME" /usr/share/jenkins/ref

# for main web interface:
EXPOSE 8080

# will be used by attached slave agents:
EXPOSE 50000

ENV COPY_REFERENCE_FILE_LOG $JENKINS_HOME/copy_reference_file.log

USER ${user}

# Install composer packages
RUN composer global config minimum-stability dev; \
	composer global config prefer-stable true; \
	composer global require phpunit/phpunit squizlabs/php_codesniffer phploc/phploc pdepend/pdepend phpmd/phpmd sebastian/phpcpd \
    mayflower/php-codebrowser theseer/phpdox:dev-master --prefer-source --no-interaction

COPY jenkins-support /usr/local/bin/jenkins-support
COPY jenkins.sh /usr/local/bin/jenkins.sh
ENTRYPOINT ["/bin/tini", "--", "/usr/local/bin/jenkins.sh"]

# from a derived Dockerfile, can use `RUN plugins.sh active.txt` to setup /usr/share/jenkins/ref/plugins from a support bundle
COPY plugins.sh /usr/local/bin/plugins.sh
COPY install-plugins.sh /usr/local/bin/install-plugins.sh

# Install jenkins-php recommended plugins
RUN install-plugins.sh checkstyle cloverphp crap4j dry htmlpublisher jdepend plot pmd violations warnings xunit
