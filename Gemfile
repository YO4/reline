source 'https://rubygems.org'

gemspec

is_unix = RUBY_PLATFORM =~ /(aix|darwin|linux|(net|free|open)bsd|cygwin|solaris|irix|hpux)/i
is_win = RUBY_PLATFORM =~ /(mswin|msys|mingw|cygwin|bccwin|wince|emc)/i

if is_unix && ENV['WITH_VTERM']
  gem "vterm", github: "ruby/vterm-gem"
  gem "yamatanooroti", github: "ruby/yamatanooroti"
end
if is_win
  gem "yamatanooroti", github: "yo4/yamatanooroti", branch: "ci_for_windows"
end

gem 'bundler'
gem 'rake'
gem 'test-unit'
