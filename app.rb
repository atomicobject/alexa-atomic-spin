require 'sinatra'
require 'json'
require 'net/http'
require 'uri'
require 'rest-client'
require 'nokogiri'
require 'alexa_verifier'
require './quell.rb'

if development?
  require 'pry'
end

module Spin
  SPIN_ROOT_URL = "https://spin.atomicobject.com/wp-json/"

  def self.readable_content(content)
    # Convert html to plain text and then split by newlines so pauses can be added
    html = Nokogiri::HTML(content)
    # Remove code snippets
    html.css("pre code").each{|p| p.swap(" Code Snippet. ")}
    # Squish multiple new lines into one
    text = html.text.gsub!(/[\n]+/, "\n");
    text.split("\n")
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

before do
  # Respond with json for all responses
  content_type :json
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

post '/rate-pain' do
  req_body = request.body.read
  puts "REQUEST BODY: #{req_body}"
  req_params = JSON.parse req_body

  session = RatePain.get_session req_params
  
  resp_text = RatePainIntents.handle_intent session, req_params
  make_ssml_response resp_text, false
end

# For debugging
get '/rate-pain' do
  puts "Received request with headers:\n#{request.env}"
  rate_pain_session = RatePainSession.new
  resp_text = rate_pain_session.rate_pain
  make_ssml_response resp_text, false
end


PADDING_LEN = 25 # for the type: "SSML" and ssml: parts
OPENING_TAG = "<speak>"
CLOSING_TAG = "</speak>"
MAX_RESPONSE_LEN = 8000 # Give extra characters for conversion to json

def post_to_ssml(post)
  read_more_text = "The remainder of this post cannot be read due to it's length, however you can read the rest at spin.atomicobject.com!"
  result = OPENING_TAG
  result = OPENING_TAG + "#{post[:title]}<break strength=\"medium\"/> by #{post[:author]}<break time=\"1s\"/>"
  result = post[:body_sections].inject(result) do |memo, section|
    next_section = "#{section}<break time=\"1s\"/>"
      if ((PADDING_LEN + memo.length + next_section.length + read_more_text.length + CLOSING_TAG.length) > MAX_RESPONSE_LEN)
        puts "Truncating post"
        break memo << read_more_text
      end
    memo << next_section
    memo
  end
  result << CLOSING_TAG
  puts "Result json length: #{result.to_json.length}" 
  result
end

def response_card_for_post(post)
  {
    "type": "Simple",
    "title": "Atomic Spin Blog Post",
    "content": "#{post[:title]}\nby #{post[:author]}\n\nRead this post at: spin.atomicobject.com"
  }
end

def make_ssml_response(text, end_session=true, card=nil)
  r = {
    "version" => "1.0",
    "sessionAttributes" => { },
    "response" => {
      "outputSpeech" => {
        "type" => "SSML",
        "ssml" => text
      },
        "shouldEndSession" => end_session
    }
  }
  r["response"]["card"] = card if card
  r.to_json
end

