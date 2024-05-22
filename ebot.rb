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
MAX_QUEUE = 50
CONTROL_SEQUENCE = "CONTROL"
CONTROL_REGEXP = /^#{CONTROL_SEQUENCE}/
SLEEP_TIME = 200

$ollama = Ollama.new(
  credentials: { address: 'http://localhost:11434' },
  options: { server_sent_events: true }
)

$bot = Discordrb::Bot.new(token: BOT_TOKEN)

$executor = Concurrent::ThreadPoolExecutor.new(
  min_threads: MIN_THREADS, max_threads: MAX_THREADS, 
  max_queue: MAX_QUEUE, fallback_policy: :discard,
)

$list = []

def task_id
  "(#{BOT_NAME} task ##{$executor.completed_task_count} " + 
  "#{$executor.queue_length + MAX_THREADS}/" +
  "#{$executor.max_queue + $executor.max_length})"
end

$bot.ready {
  msg = "#{CONTROL_SEQUENCE} #{BOT_NAME} is up."
  $bot.send_message(CHANNEL_ID, msg)
  $stderr.print msg, "\n"
  $bot.update_status('online', nil, nil)
}

$bot.message(:channel => CHANNEL_ID) {|e|
  if e.channel.id != CHANNEL_ID
    $stderr.print "returning because #{e.channel.id} is not #ebot. (#{task_id})\n"
    next
  end
  if CONTROL_REGEXP.match(e.content)
    $stderr.print "ignored \"#{e.content}\" because it is a CONTROL. (#{task_id})\n"
    next
  end
  if $executor.queue_length == $executor.max_queue
    msg = "ignored \"#{e.content}\" because the queue is full. (#{task_id})\n"
    $stderr.print "#{msg}\n"
    e.respond("#{CONTROL_SEQUENCE} #{msg}")
    next
  end
  $executor.post do
    $bot.update_status('dnd', nil, nil)
    if $executor.queue_length < $executor.max_queue / 2
      $list.push(e)
      e.respond(ask())
    else
      if rand(2) == 0
        e.respond("CONTROL Skipped because max_queue was hit. #{task_id}" )
      else
        $list.push(e)
        e.respond(ask())
      end
    end
    $bot.update_status('online', nil, nil)
  end
}

def choose
  # take oldest non-bot message of oldest bot message
  event = nil
  $list.each {|e|
    if !e.author.bot_account
      event = e
      $list.delete(e)
      break
    end
  }
  event ||= $list.shift
  $stderr.print "list size: #{$list.size} except this.\n"
  $stderr.print "author username: #{event.author.username}\n"
#  $stderr.print "author bot_account?: #{event.author.bot_account}\n"
#  $stderr.print "channel: #{event.channel}\n"
#  $stderr.print "content: #{event.content}\n"
#  $stderr.print "file: #{event.file}\n"
#  $stderr.print "message: #{event.message}\n"
#  $stderr.print "server: #{event.server}\n"
#  $stderr.print "timestamp: #{event.timestamp}\n"
#  $stderr.print "bot: #{event.bot}\n"
  event
end

def ask
  event = choose
  prompt = event.content
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
  "#{s} #{task_id}"[0..1999] 
end

$bot.run
