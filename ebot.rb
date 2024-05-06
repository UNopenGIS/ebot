require 'dotenv/load'
require 'ollama-ai'
require 'discordrb'
require 'concurrent'
require 'json'

BOT_TOKEN = ENV['BOT_TOKEN']
CHANNEL_ID = ENV['CHANNEL_ID'].to_i
MODEL = ENV['MODEL']

OLLAMA_URL = 'http://localhost:11434'
BOT_NAME = "ebot/#{MODEL}@#{`hostname -s`.strip}"
PROMPT_EXTRA = "\n\nAnswer in less than 1900 characters. Finalize with a small question."
MIN_THREADS = 1
MAX_THREADS = 1
MAX_QUEUE = 2
CONTROL_SEQUENCE = "CONTROL"
CONTROL_REGEXP = /^#{CONTROL_SEQUENCE}/

$ollama = Ollama.new(
  credentials: { address: 'http://localhost:11434' },
  options: { server_sent_events: true }
)

$bot = Discordrb::Bot.new(token: BOT_TOKEN)

$task_queue = Concurrent::ThreadPoolExecutor.new(
  min_threads: MIN_THREADS, max_threads: MAX_THREADS, 
  max_queue: MAX_QUEUE, fallback_policy: :discard
)

$bot.ready {
  msg = "#{CONTROL_SEQUENCE} #{BOT_NAME} is up."
  $bot.send_message(CHANNEL_ID, msg)
  $stderr.print msg, "\n"
  $bot.update_status('online', nil, nil)
}

$bot.message {|e|
  if e.channel.id != CHANNEL_ID
    $stderr.print "returning because #{e.channel.id} is not #ebot.\n"
    next
  end
  if CONTROL_REGEXP.match(e.content)
    $stderr.print "ignored \"#{e.content}\" because it is a CONTROL.\n"
    next
  end
  if $task_queue.queue_length == $task_queue.max_queue
    msg = "ignored \"#{e.content}\" because the queue is full.\n"
    $stderr.print "#{msg}\n"
    e.respond("#{CONTROL_SEQUENCE} #{msg}")
    next
  end
  $task_queue.post do
    $bot.update_status('dnd', nil, nil)
    e.respond(ask(e.content))
    $bot.update_status('online', nil, nil)
  end
}

def ask(prompt)
  question = "#{prompt.sub(/\(ebot.*\)$/, '')} #{PROMPT_EXTRA}"
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
  "#{s} (#{BOT_NAME} #{$task_queue.queue_length + 1}/#{$task_queue.max_queue + $task_queue.max_length})"
end

$bot.run
