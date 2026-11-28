Gem::Specification.new do |s|
  s.name = "why-now-account-briefs"
  s.version = "1.0.0"
  s.summary = "Ruby CLI that turns a target-account CSV with timing signals into one Markdown brief per account plus a tier and vendor index. Accounts with"
  s.description = "Ruby CLI that turns a target-account CSV with timing signals into one Markdown brief per account plus a tier and vendor index. Accounts without a why-now signal are skipped, not guessed."
  s.authors = ["Jainendra Ojha"]
  s.email = ["account@onegtmlab.dev"]
  s.license = "MIT"
  s.homepage = "https://www.onegtmlab.dev/case-studies/from-zero-outbound-infrastructure-to-20k-enriched-accounts-in-45-days"
  s.metadata = { "source_code_uri" => "https://github.com/jaizendra-netizen/why-now-account-briefs" }
  s.required_ruby_version = ">= 2.7"
  s.files = Dir["lib/**/*.rb", "bin/*", "LICENSE", "README.md"]
  s.bindir = "bin"
  s.executables = ["why-now"]
end
