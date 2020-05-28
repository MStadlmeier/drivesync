FROM ruby:2.6.6
RUN git clone https://github.com/MStadlmeier/drivesync.git /drivesync

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y locales

RUN sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
    dpkg-reconfigure --frontend=noninteractive locales && \
    update-locale LANG=en_US.UTF-8

ENV LANG en_US.UTF-8 
ENV LC_ALL en_US.UTF-8

WORKDIR /drivesync
RUN bundle update --bundler \
    && bundle install

