require 'sinatra'
require 'json'
require 'net/http'
require 'uri'
require 'rest-client'
require 'nokogiri'
require 'alexa_verifier'
#require 'pry'

module Spin
  SPIN_ROOT_URL = "https://spin.atomicobject.com/wp-json/"

  def self.readable_content(content)
    # Convert html to plain text and then split by newlines so pauses can be added
    Nokogiri::HTML(content).text.split("\n")
  end

  def self.prepare_post_for_reading(post_json)
    {
      title: post_json["title"],
      author: post_json["author"]["name"],
      # Convert the html body to readable content
      body_sections: readable_content(post_json["content"])
    }
  end

  def self.latest_post
    url = URI::join(SPIN_ROOT_URL, 'posts')
    response = RestClient.get url.to_s, params: {filter: {posts_per_page: 1}}
    response_json = JSON.parse response.body
    post = response_json.first
    prepare_post_for_reading post
  end
end

configure do
  $stdout.sync = true
  verifier = AlexaVerifier.build do |c|
    c.verify_signatures = true
    c.verify_timestamps = true
    c.timestamp_tolerance = 60 # seconds
  end
  set :cert_verifier, verifier
end

# For Alexa
post '/latest-post' do
  verification_success = settings.cert_verifier.verify!(
    request.env["HTTP_SIGNATURECERTCHAINURL"],
    request.env['HTTP_SIGNATURE'], 
    request.body.read
  )
  raise "Cert validation failed" unless verification_success

  post = Spin.latest_post
  ssml = post_to_ssml(post)
  make_ssml_response(ssml)
end

# For debugging
get '/latest-post' do
  puts "REQUEST BODY: #{request.body}"
  post = Spin.latest_post
  ssml = post_to_ssml(post)
  make_ssml_response(ssml)
end

def post_to_ssml(post)
  result = "<speak>"
  result << "#{post[:title]}<break strength=\"medium\"/> by #{post[:author]}<break time=\"1s\"/>"
  result = post[:body_sections].inject(result) do |memo, section|
    memo << "#{section}<break time=\"1s\"/> "
  end
  result << "</speak>"
end

def make_ssml_response(text)
  {
    "version" => "1.0",
    "sessionAttributes" => { },
    "response" => {
      "outputSpeech" => {
        "type" => "SSML",
        "ssml" => text
      },
      "shouldEndSession" => true
    }
  }.to_json
end

