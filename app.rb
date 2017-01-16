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
      body_sections: readable_content(post_json["content"]),
      url: post_json["url"]
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
  puts "Received request with headers:\n#{request.env}"
  verification_success = settings.cert_verifier.verify!(
    request.env["HTTP_SIGNATURECERTCHAINURL"],
    request.env['HTTP_SIGNATURE'], 
    request.body.read
  )
  raise "Cert validation failed" unless verification_success

  post = Spin.latest_post
  ssml = post_to_ssml(post)
  card = response_card_for_post(post)
  make_ssml_response(ssml, card)
end

# For debugging
get '/latest-post' do
  puts "REQUEST BODY: #{request.body}"
  post = Spin.latest_post
  ssml = post_to_ssml(post)
  card = response_card_for_post(post)
  make_ssml_response(ssml, card)
end

OPENING_TAG = "<speak>"
CLOSING_TAG = "</speak>"
MAX_RESPONSE_LEN = 8000

def post_to_ssml(post)
  read_more_text = "The remainder of this post cannot be read due to it's length, however you can read the rest at spin.atomicobject.com!"
  result = OPENING_TAG
  result << "#{post[:title]}<break strength=\"medium\"/> by #{post[:author]}<break time=\"1s\"/>"
  result = post[:body_sections].inject(result) do |memo, section|
    next_section = "#{section}<break time=\"1s\"/>"
    if ((memo.length + next_section.length + read_more_text.length + CLOSING_TAG.length) > MAX_RESPONSE_LEN)
      break memo << read_more_text
    end
    memo << next_section
  end
  result << CLOSING_TAG
end

def response_card_for_post(post)
  {
    "type": "Simple",
    "title": "Atomic Spin Blog Post",
    "content": "#{post[:title]}\nby #{post[:author]}\n\nRead this post at: spin.atomicobject.com"
  }
end

def make_ssml_response(text, card)
  r = {
    "version" => "1.0",
    "sessionAttributes" => { },
    "response" => {
      "outputSpeech" => {
        "type" => "SSML",
        "ssml" => text
      },
      "shouldEndSession" => true
    }
  }
  r["response"]["card"] = card if card
  r.to_json
end

