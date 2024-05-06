require 'dotenv/load'
require 'ollama-ai'
require 'discordrb'
require 'json'

OLLAMA_URL = 'http://localhost:11434'
BOT_TOKEN = ENV['BOT_TOKEN']
MODEL = 'tinyllama'
CHANNEL_ID = ENV['CHANNEL_ID'].to_i
BOT_NAME = "ebot/#{MODEL}@#{`hostname -s`.strip}"
PROMPT_EXTRA = "Answer in less than 1900 characters. Finalize with a small question."

$ollama = Ollama.new(
  credentials: { address: 'http://localhost:11434' },
  options: { server_sent_events: true }
)

$bot = Discordrb::Bot.new(token: BOT_TOKEN)

$bot.ready {
  $bot.send_message(CHANNEL_ID, "#{BOT_NAME} is up.")
  $bot.online
}

$bot.message {|e|
  if e.channel.id == CHANNEL_ID
    $bot.dnd
    e.respond(ask(e.content))
    $bot.online
  else
    $stderr.print "returning because #{e.channel.id} is not #ebot.\n"
  end
}

def ask(prompt)
  question = "#{prompt} #{PROMPT_EXTRA}"
  $stderr.print "Question: #{question}\n\n"
  s = ""
  $ollama.generate({
    model: MODEL,
    prompt: question
  }) {|event, raw|
    $stderr.print event['response']
    s += event['response']
  }
  $stderr.print "\n\n\n"
  "#{s} (#{BOT_NAME})"
end

$bot.run
