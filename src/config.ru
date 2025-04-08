#!/usr/bin/env ruby
require 'sinatra'
require 'json'
require 'sinatra/reloader'

get '*/list*', &-> { slim :list }
get '*', &-> { slim :index }

run Sinatra::Application