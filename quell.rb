
class RatePain
  @@sessions = nil

  def self.get_session(request)
    if @@sessions.nil?
      @@sessions = {}
    end

    new_session = request['session']['new']
    session_id = request['session']['sessionId']

    if new_session
      puts "Creating a new session"
      session = RatePainSession.new(session_id)
      @@sessions[session_id] = session
    else
      puts "Continuing Session"
      session = @@sessions[session_id]
      puts "Found existing session #{session.inspect}"
    end
    session
  end

end

class RatePainIntents

  def self.handle_intent session, request
    intent_info = request['request']['intent']
    intent_name = intent_info['name']
    puts "Session: #{session.inspect}"

    if intent_name == 'RatePain'
      session.prompt_to_rate
    elsif intent_name =='PainRating' 
      score = intent_info['slots']['PainScore']['value']
      session.submit_score score
    else
      raise 'Unknown Intent'
    end
  end
end

class RatePainSession

  def initialize(session_id)
    @session_id = session_id
    @ratings = [
      {
        prompt: "On a scale of one to ten, how would you rate your pain over the last 24 hours?"
      },
      {
        prompt: "How much has pain <break time='1ms'/> affected your sleep <break time='1ms'/> over the last 24 hours?"
      },
      {
        prompt: "How much has pain <break time='1ms'/> affected your activity level <break time='1ms'/> over the last 24 hours?"
      },
      {
        prompt: "How much has pain <break time='1ms'/> affected your mood <break time='1ms'/> over the last 24 hours?"
      }
    ]
  end

  def is_finished?
    current_step().nil?
  end

  def current_step
    @ratings.find {|r| r[:answer].nil? }
  end

  def prompt_to_rate
    step = current_step
    if current_step.nil?
      puts "RATING IS OVER: #{@ratings}"
      text_to_ssml("Your ratings have been submitted. Thank you.")
    else
      text_to_ssml(step[:prompt])
    end
  end

  def submit_score(score)
    step = current_step
    step[:answer] = score
    puts "Saved Score: #{step}"
    prompt_to_rate
  end

  def text_to_ssml(text)
    result = OPENING_TAG
    result = result + text
    result = result + CLOSING_TAG
  end

end
