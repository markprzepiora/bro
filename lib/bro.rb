#!/usr/bin/env ruby
require 'rubygems'
require 'json'
require 'commander/import'
require 'highline'
require 'smart_colored'
require 'rest-client'

$LOAD_PATH << "."
require_relative 'bro/state.rb'
require_relative 'bro/bro_state.rb'
require_relative 'bro/string_hacks.rb'
require_relative 'bro/version.rb'
include Bro

URL = ENV["BROPAGES_URL"] || 'http://bropages.org'
FILE = ENV["HOME"] + '/.bro'
BRO_OR_SIS = if $PROGRAM_NAME =~ /sis$/
               "sis"
             else
               "bro"
             end
BRO_OR_SIS_CAPITALIZED = BRO_OR_SIS.capitalize

program :name, BRO_OR_SIS
program :version, Bro::VERSION
program :description, "Highly readable supplement to man pages.\n\nShows simple, concise examples for commands."
default_command :lookup

state = Bro::BroState.new({:file => FILE})

command :thanks do |c|
  c.syntax = "#{BRO_OR_SIS} thanks [COMMAND]"
  c.summary = "Upvote an entry, #{BRO_OR_SIS}"
  c.description = "Upvote a #{BRO_OR_SIS} entry. If called without a COMMAND argument, it will upvote the last thing you looked up with #{BRO_OR_SIS}"
  c.example "Upvote the #{BRO_OR_SIS} entry for curl", "#{BRO_OR_SIS} thanks curl"
  c.action do |args, options|
    begin
      login_details = state.check_email
    rescue => e
      say "Sorry, you can't do this without email verification".sorry
      say "#{e}"
    end
    unless login_details.nil?
      cmd = state.read_state[:cmd]

      if cmd.nil?
        say "\nYou must first look up a command before downvoting. For example: #{BRO_OR_SIS} curl\n\n".sorry
        return
      end

      idkey = args[0]
      if idkey.nil?
        idkey = "1"
      end
      id = state.read_state[idkey.intern]

      if id.nil?
        say "That id (#{idkey}) does not exist for #{cmd}, try another one".sorry
      end

      unless id.nil?
        begin
          res = RestClient.get URL + "/thanks/#{id}", { params: login_details }
        rescue => e
          say e.message
          say "There was a problem thanking the #{cmd} entry. This entry may not exist or bropages.org may be down".problem
        else
          say "You just gave thanks to an entry for #{cmd}!".status
          say "You rock!".success
        end
      end
    end
  end
end

noblock = lambda { |c|
  c.syntax = "#{BRO_OR_SIS} ...no [ID]"
  c.summary = "Downvote an entry, #{BRO_OR_SIS}"
  c.description = "Downvote a #{BRO_OR_SIS} entry for the last command you looked up. If called without ID, it will downvote the top entry of the last command you looked up."
  c.example "Downvote the #{BRO_OR_SIS} entry for curl", "#{BRO_OR_SIS} curl\n\n#{BRO_OR_SIS} ...no"
  c.action do |args, options|
    begin
      login_details = state.check_email
    rescue
      say "Sorry, you can't do this without email verification".sorry
      say "#{e}"
    end
    unless login_details.nil?

      cmd = state.read_state[:cmd]

      if cmd.nil?
        say "\nYou must first look up a command before downvoting. For example: #{BRO_OR_SIS} curl\n\n".sorry
        return
      end

      idkey = args[0]
      if idkey.nil?
        idkey = "1"
      end
      id = state.read_state[idkey.intern]

      if id.nil?
        say "That id (#{idkey}) does not exist for #{cmd}, try another one".sorry
      end

      unless id.nil?
        begin
          res = RestClient.get URL + "/no/#{id}", { params: login_details }
        rescue => e
          say "There was a problem downvoting the #{cmd} entry. This entry may not exist or bropages.org may be down".problem
          say e
        else
          say "You just downvoted an entry for #{cmd}".status
          say "You rock!".success
        end
      end
    end
  end
}

command :"...no", &noblock
command :no, &noblock

command :add do |c|
  c.syntax = "#{BRO_OR_SIS} add [COMMAND] [-m MESSAGE]"
  c.summary = "Add an entry, #{BRO_OR_SIS}"
  c.description = <<-QQQ.unindent
  This adds an entry to the http://bropages.org database.
  
  Called without parameters will add an entry for the last thing you looked up with #{BRO_OR_SIS}.
  QQQ
  c.example 'Launch your editor to add an entry for curl', "#{BRO_OR_SIS} add curl"
  c.example 'Quickly add an entry for curl', BRO_OR_SIS + ' add curl -m "curl http://google.com"'
  # TODO c.option '-m', 'An optional inline entry. This won\'t trigger a system editor to open'
  c.action do |args, options|
    begin
      login_details = state.check_email
    rescue => e
      say "Sorry, you can't do this without email verification".sorry
      say e
    end

    unless login_details.nil?

      cmd = state.get_arg_or_last_command args

      if cmd.nil?
        say "\nYou must enter a command after #{BRO_OR_SIS + " add".status}.\n\nFor example: #{BRO_OR_SIS + " add".success} #{"curl".success.underline}\n\n"
      else
        prompt = <<-QQQ.unindent
          #~ #{BRO_OR_SIS_CAPITALIZED} entry for command '#{cmd}'
          #~ Provide a useful example for how to use '#{cmd}'
          #~ Comments starting with #~ are removed
          #~
          #~ Example for command 'man':
          #~ # Opens up the manual page for the command 'ls'
          #~ man ls
          
          
          # your_comment_here
          your_command_here
          QQQ
        entry = ask_editor prompt, "vim"
        if entry.gsub(prompt, '').strip.length > 0
          if agree "Submit this entry for #{cmd}? [Yn] "
            say "All right, sending your entry...".status
            begin
              res = RestClient.post URL + '/', login_details.merge({ entry: { cmd: cmd, msg: entry}, format: 'json', multipart: true })
            rescue => e
              say e.message
              file = "/tmp/#{cmd}.bro"

              # increment file name as to not overwrite anything
              i = 1
              while File.exist?(file)
                file = "/tmp/#{cmd}#{i}.bro"
                i += 1
              end

              # write message to file
              File.open(file, 'w') do |f|
                f.write entry
              end
              say "Woops. There was an error! Your entry was saved to #{file}".problem
            else
              say "Successfully submitted.".success
            end
          end
        else
          say "Canceled. Did not submit entry for '#{cmd}'".status
        end
      end
    end
  end
end

command :lookup do |c|
  c.syntax = "#{BRO_OR_SIS} [COMMAND]"
  c.summary = "Lookup an entry, #{BRO_OR_SIS}. Or just call #{BRO_OR_SIS} [COMMAND]"
  c.description = "This looks up entries in the http://bropages.org database."
  c.example "Look up the #{BRO_OR_SIS} entries for curl", "#{BRO_OR_SIS} curl"
  c.action do |args, options|
    if args.empty?
      say <<-QQQ.unindent
      #{"#{BRO_OR_SIS_CAPITALIZED}! Specify a command first!".colored.red}
      
      \t* For example try #{BRO_OR_SIS + " curl".colored.green}
      
      \t* Use #{BRO_OR_SIS + " help".colored.yellow} for more info
      
      QQQ
    else
      # the display string for the command
      cmd_display = args.join(" ")

      # the server argument for the command
      cmd = args.join("%20")

      state.reset_lookup_ids()

      # write to ~/.bro file with last command
      state.write_state({ cmd: cmd_display })

      # connect to webservice for entry
      error = false
      begin
        res = RestClient.get URL + '/' + cmd + '.json'
      rescue => e
        say <<-QQQ.unindent
        The #{cmd_display.colored.yellow} command isn't in our database.
        
        \t* Typing #{BRO_OR_SIS + " add".colored.green.underline} will let you add #{cmd_display.colored.yellow} to our database!

        \t* There's nothing to lose by typing #{BRO_OR_SIS + " add".colored.red.underline}, it will just launch an editor with instructions.
        
        \t* Need help? Visit #{"http://bropages.org/help".colored.underline}
        
        QQQ
        error = true
      end

      unless error
        enable_paging
        list = JSON.parse res
        s = list.length == 1 ? 'y' : 'ies'

        say <<-QQQ.unindent
        #{"#{list.length} entr#{s} for #{cmd_display}".status.underline} #{"-- submit your own example with \"#{BRO_OR_SIS} add #{cmd_display}\"".colored.yellow}
        
        QQQ

        sep = ""
        (HighLine::SystemExtensions.terminal_size[0] - 5).times { sep += "." }
        sep += "\n"

        i = 0
        isDefault = true
        list.each {|data|
            i += 1

            obj = {}
            obj["#{i}"] = data['id']
            state.write_state(obj)

            days = (DateTime.now - DateTime.parse(data['updated_at'])).ceil.to_i

            body = data['msg']

            body = body.gsub(/^([^#][^\n]*)$/, "\\1".important)

            say sep + "\n" if i > 1

            say body + "\n\n"

            upstr = "#{BRO_OR_SIS} thanks"
            upstr += " #{i}" unless isDefault
            downstr = "#{BRO_OR_SIS} ...no"
            downstr += " #{i}" unless isDefault

            msg = "\t#{upstr.colored.green}\tto upvote (#{data['up']})\n\t#{downstr.colored.red}\tto downvote (#{data['down']})"
            if days > 0
              #msg += "\tlast updated\t#{days} days ago"
            end
            say msg + "\n\n"
            isDefault = false
        }

      end
    end
  end
end
