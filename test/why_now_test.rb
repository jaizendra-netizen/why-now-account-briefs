# frozen_string_literal: true
require 'minitest/autorun'
require 'tmpdir'
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'why_now'

class WhyNowTest < Minitest::Test
  EX = File.expand_path('../examples', __dir__)

  def recs
    WhyNow.parse_csv(File.read(File.join(EX, 'accounts.csv')))
  end

  def test_csv_quotes_commas_and_doubled_quotes
    r = recs
    assert_equal 4, r.size
    assert_includes r[0]['why_now'], 'scanner, and a VP'
    assert_equal 'Open a conversation about "consolidation"', r[0]['notes']
  end

  def test_csv_handles_crlf_bom_and_embedded_newline
    rows = WhyNow.parse_csv("﻿a,b\r\n1,\"x\ny\"\r\n")
    assert_equal [{ 'a' => '1', 'b' => "x\ny" }], rows
  end

  def test_csv_empty_raises
    assert_raises(WhyNow::Error) { WhyNow.parse_csv('') }
  end

  def test_render_defaults_and_personas
    out = WhyNow.render(WhyNow::DEFAULT_TEMPLATE, recs[1])
    assert_includes out, '# Contoso Example'
    assert_includes out, '- Persona A: CISO'
    assert_includes out, 'Using today: Vendor B'
    out2 = WhyNow.render('{{current_vendor|unknown}} / {{ tier }}', 'tier' => '3')
    assert_equal 'unknown / 3', out2
  end

  def test_personas_plain_and_empty
    assert_equal "- VP\n- Director", WhyNow.personas_list('VP;Director')
    assert_equal '_none recorded_', WhyNow.personas_list('')
  end

  def test_missing_why_now_is_skipped_not_written
    Dir.mktmpdir do |d|
      res = WhyNow.build(recs, outdir: d, today: Date.new(2026, 11, 20))
      assert_equal 3, res[:written]
      assert_equal 1, res[:skipped].size
      assert_equal 'Fabrikam Example', res[:skipped][0][0]
      refute File.exist?(File.join(d, 'fabrikam-example.md'))
    end
  end

  def test_duplicate_account_names_get_distinct_files
    Dir.mktmpdir do |d|
      WhyNow.build(recs, outdir: d)
      assert File.exist?(File.join(d, 'northwind-example.md'))
      assert File.exist?(File.join(d, 'northwind-example-2.md'))
    end
  end

  def test_stale_signals_are_skipped
    Dir.mktmpdir do |d|
      res = WhyNow.build(recs, outdir: d, stale_days: 30, today: Date.new(2026, 11, 20))
      names = res[:skipped].map(&:first)
      assert_includes names, 'Contoso Example'
      assert_equal 2, res[:written]
    end
  end

  def test_bad_signal_date_reported
    p = WhyNow.problems({ 'account' => 'A', 'why_now' => 'x', 'signal_date' => '10/11/2026' }, required: [], stale_days: 30)
    assert_match(/not YYYY-MM-DD/, p.first)
  end

  def test_index_groups_by_tier_and_counts_vendors
    Dir.mktmpdir do |d|
      WhyNow.build(recs, outdir: d, today: Date.new(2026, 11, 20))
      idx = File.read(File.join(d, 'INDEX.md'))
      assert_includes idx, '## Tier: 1'
      assert_includes idx, '- Vendor A: 2'
      assert_includes idx, 'Fabrikam Example: missing why_now'
    end
  end

  def test_cli_exit_code_and_custom_template
    Dir.mktmpdir do |d|
      bin = File.expand_path('../bin/why-now', __dir__)
      out = `ruby #{bin} #{EX}/accounts.csv -o #{d} -t #{EX}/template.md`
      refute $?.success?, 'skipped rows must give a non-zero exit'
      assert_match(/3 briefs written/, out)
      assert_includes File.read(File.join(d, 'contoso-example.md')), 'Tier 2 | currently on Vendor B'
    end
  end
end
