# 2.0.0

* Rails 8.1 / Ruby 4.0.5 support: bump `omniauth` from `~> 1.2` to `~> 2.0`
  (omniauth 1.x is incompatible with Rack 3), and loosen `nokogiri` (>= 1.10)
  and `addressable` (>= 2.3).
* Verified the CAS strategy loads and the request phase redirects on omniauth
  2.x / Rack 3 / Ruby 4. The logout (single-sign-out) callback already returns a
  Rack 3-compatible response.
* Add a self-contained smoke harness (`test/smoke.rb`, OmniAuth::Builder app) and
  a CI matrix over Ruby 4.0.5 / 3.4 / 3.2.

Note: omniauth 2 defaults the request phase to POST-only; consuming apps need
`omniauth-rails_csrf_protection` (or to allow GET) — an app-side change.

# Change Log

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/) and this
project adheres to [Semantic Versioning](http://semver.org/)

## 1.1.1 - 2016-09-19

### Changed

* Relax gemspec requirements, to add support for Rails 5.

Note that the only tested versions of Ruby are now 2.1, 2.2, and 2.3 - older
versions of Ruby should work, but are no longer officially supported.
