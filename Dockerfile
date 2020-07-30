FROM ruby:2.5

RUN apt-get update && apt-get upgrade &&\
    apt-get install ca-certificates -y && update-ca-certificates

# throw errors if Gemfile has been modified since Gemfile.lock
RUN bundle config --global frozen 1
RUN gem install bundler
RUN gem update --system

WORKDIR /usr/src/app

COPY . ./

RUN bundle install

RUN chmod +x ./augmend_server.rb

CMD ["ruby", "/usr/src/app/augmend_server.rb"]