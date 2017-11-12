
class RatePainSession

  def rate_pain
    text_to_ssml "On a scale of one to ten, how would you rate your pain over the last 24 hours?"
  end

  def text_to_ssml(text)
    result = OPENING_TAG
    result = result + text
    result = result + CLOSING_TAG
  end

end
