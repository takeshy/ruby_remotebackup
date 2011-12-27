# Generated by jeweler
# DO NOT EDIT THIS FILE DIRECTLY
# Instead, edit Jeweler::Tasks in Rakefile, and run 'rake gemspec'
# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = "remotebackup"
  s.version = "0.70.0"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["Takeshi Morita"]
  s.date = "2011-12-27"
  s.description = "version backup tool using scp."
  s.email = "laten@nifty.com"
  s.executables = ["remote_backup", "restore_backup"]
  s.extra_rdoc_files = [
    "ChangeLog",
    "LICENSE.txt",
    "README",
    "README.rdoc"
  ]
  s.files = [
    "ChangeLog",
    "Gemfile",
    "LICENSE.txt",
    "README",
    "README.rdoc",
    "Rakefile",
    "VERSION",
    "bin/remote_backup",
    "bin/restore_backup",
    "lib/node.rb",
    "lib/remotebackup.rb"
  ]
  s.homepage = "http://github.com/takeshy/remotebackup"
  s.licenses = ["MIT"]
  s.require_paths = ["lib"]
  s.rubygems_version = "1.8.11"
  s.summary = "version backup tool using scp."

  if s.respond_to? :specification_version then
    s.specification_version = 3

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
      s.add_runtime_dependency(%q<net-scp>, [">= 0"])
      s.add_development_dependency(%q<rspec>, ["~> 2.3.0"])
      s.add_development_dependency(%q<bundler>, ["~> 1.0.0"])
      s.add_development_dependency(%q<jeweler>, ["~> 1.6.4"])
      s.add_development_dependency(%q<rcov>, [">= 0"])
    else
      s.add_dependency(%q<net-scp>, [">= 0"])
      s.add_dependency(%q<rspec>, ["~> 2.3.0"])
      s.add_dependency(%q<bundler>, ["~> 1.0.0"])
      s.add_dependency(%q<jeweler>, ["~> 1.6.4"])
      s.add_dependency(%q<rcov>, [">= 0"])
    end
  else
    s.add_dependency(%q<net-scp>, [">= 0"])
    s.add_dependency(%q<rspec>, ["~> 2.3.0"])
    s.add_dependency(%q<bundler>, ["~> 1.0.0"])
    s.add_dependency(%q<jeweler>, ["~> 1.6.4"])
    s.add_dependency(%q<rcov>, [">= 0"])
  end
end

