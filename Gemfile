source 'https://rubygems.org'

gemspec

is_unix = RUBY_PLATFORM =~ /(aix|darwin|linux|(net|free|open)bsd|cygwin|solaris|irix|hpux)/i

if is_unix && ENV['WITH_VTERM']
  gem "vterm", github: "ruby/vterm-gem"
  gem "yamatanooroti", github: "ruby/yamatanooroti"
end

if Gem.win_platform?
  gem "yamatanooroti", github: "yo4/yamatanooroti", branch: "ci_for_windows"
  gem "fiddle", '>= 1.0.8' if
    (RUBY_ENGINE == "ruby" && RUBY_VERSION >= '3.4') ||
    Gem::Version.new("1.0.8") > begin
      require 'fiddle'
      Gem::Version.new(Fiddle::VERSION)
    rescue
      Gem::Version.new("0.0.0")
    end
end

gem 'bundler'
gem 'rake'
gem 'test-unit'
