# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = %q{hexwrench}
  s.version = "0.2.1"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["Eric Monti"]
  s.date = %q{2009-06-17}
  s.default_executable = %q{hexwrench}
  s.description = %q{A wxwidgets-based hex editor written in ruby}
  s.email = %q{emonti@matasano.com}
  s.executables = ["hexwrench"]
  s.extra_rdoc_files = ["History.txt", "README.rdoc", "bin/hexwrench", "lib/hexwrench/build_xrc.sh", "lib/hexwrench/ui/gui.xrc"]
  s.files = ["History.txt", "README.rdoc", "Rakefile", "bin/hexwrench", "hexwrench.gemspec", "lib/hexwrench.rb", "lib/hexwrench/build_xrc.sh", "lib/hexwrench/data_inspector.rb", "lib/hexwrench/edit_frame.rb", "lib/hexwrench/edit_window.rb", "lib/hexwrench/gui.rb", "lib/hexwrench/stringsgrid.rb", "lib/hexwrench/stringslist.rb", "lib/hexwrench/stringsvlist.rb", "lib/hexwrench/ui/gui.xrc", "samples/colorize_ascii.rb", "tasks/ann.rake", "tasks/bones.rake", "tasks/gem.rake", "tasks/git.rake", "tasks/notes.rake", "tasks/post_load.rake", "tasks/rdoc.rake", "tasks/rubyforge.rake", "tasks/setup.rb", "tasks/spec.rake", "tasks/svn.rake", "tasks/test.rake"]
  s.homepage = %q{http://emonti.github.com/hexwrench}
  s.rdoc_options = ["--line-numbers", "--main", "README.rdoc"]
  s.require_paths = ["lib"]
  s.rubyforge_project = %q{hexwrench}
  s.rubygems_version = %q{1.3.4}
  s.summary = %q{A wxwidgets-based hex editor written in ruby}

  if s.respond_to? :specification_version then
    current_version = Gem::Specification::CURRENT_SPECIFICATION_VERSION
    s.specification_version = 3

    if Gem::Version.new(Gem::RubyGemsVersion) >= Gem::Version.new('1.2.0') then
      s.add_runtime_dependency(%q<wxruby>, [">= 2.0.0"])
      s.add_runtime_dependency(%q<rbkb>, [">= 0.6.8.1"])
      s.add_development_dependency(%q<bones>, [">= 2.5.1"])
    else
      s.add_dependency(%q<wxruby>, [">= 2.0.0"])
      s.add_dependency(%q<rbkb>, [">= 0.6.8.1"])
      s.add_dependency(%q<bones>, [">= 2.5.1"])
    end
  else
    s.add_dependency(%q<wxruby>, [">= 2.0.0"])
    s.add_dependency(%q<rbkb>, [">= 0.6.8.1"])
    s.add_dependency(%q<bones>, [">= 2.5.1"])
  end
end
