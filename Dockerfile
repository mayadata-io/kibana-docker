# This Dockerfile was generated from the template at templates/Dockerfile.j2
FROM centos:7
EXPOSE 5601

# Add Reporting dependencies.
RUN yum update -y && yum install -y fontconfig freetype && yum clean all

WORKDIR /usr/share/kibana

# Set gid to 0 for kibana and make group permission similar to that of user
# This is needed, for example, for Openshift Open:
# https://docs.openshift.org/latest/creating_images/guidelines.html
# and allows Kibana to run with an uid
COPY ./kibana-6.4.0-SNAPSHOT-linux-x86_64.tar.gz /usr/share/kibana
RUN tar --strip-components=1 -zxf kibana-6.4.0-SNAPSHOT-linux-x86_64.tar.gz && \
  ln -s /usr/share/kibana /opt/kibana && \
  chown -R 1000:0 . && \
  chmod -R g=u /usr/share/kibana && \
  find /usr/share/kibana -type d -exec chmod g+s {} \;

ENV ELASTIC_CONTAINER true
ENV PATH=/usr/share/kibana/bin:$PATH

# Install kibana own-home plugin
COPY ./own_home-6.4.0.zip /usr/share/
RUN /usr/share/kibana/bin/kibana-plugin install file:///usr/share/own_home-6.4.0.zip

# remove optimize directory from root permission as it is not being deleted by kibana and gives permission denied error
# during the server optimizer run
# This error occured when plugin is disabled from kibana config (xpack.apm.enabled: false)
RUN rm -rf /usr/share/kibana/optimize/bundles

# Set some Kibana configuration defaults.
COPY --chown=1000:0 ./build/kibana/config/kibana-oss.yml /usr/share/kibana/config/kibana.yml

# Add the launcher/wrapper script. It knows how to interpret environment
# variables and translate them to Kibana CLI options.
COPY --chown=1000:0 ./build/kibana/bin/kibana-docker /usr/local/bin/

# Add a self-signed SSL certificate for use in examples.
COPY --chown=1000:0 ./build/kibana/ssl/kibana.example.org.* /usr/share/kibana/config/

# Ensure gid 0 write permissions for Openshift.
RUN find /usr/share/kibana -gid 0 -and -not -perm /g+w -exec chmod g+w {} \;

# Provide a non-root user to run the process.
RUN groupadd --gid 1000 kibana && \
    useradd --uid 1000 --gid 1000 \
      --home-dir /usr/share/kibana --no-create-home \
      kibana

USER kibana

LABEL org.label-schema.schema-version="1.0" \
  org.label-schema.vendor="Elastic" \
  org.label-schema.name="kibana" \
  org.label-schema.version="6.4.0" \
  org.label-schema.url="https://www.elastic.co/products/kibana" \
  org.label-schema.vcs-url="https://github.com/elastic/kibana-docker" \
license="Apache-2.0"
CMD ["/usr/local/bin/kibana-docker"]
