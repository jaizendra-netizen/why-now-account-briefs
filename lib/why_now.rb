# frozen_string_literal: true
require 'date'
require 'fileutils'

# Builds one Markdown research brief per target account from a CSV and a template.
module WhyNow
  class Error < StandardError; end

  DEFAULT_TEMPLATE = <<~MD
    # {{account}}

    - Domain: {{domain|not recorded}}
    - Tier: {{tier|unassigned}}
    - Using today: {{current_vendor|not recorded}}

    ## Why now

    {{why_now|MISSING: no timing signal recorded. Do not contact on fit alone.}}

    Signal date: {{signal_date|not recorded}}. Source: {{signal_source|not recorded}}.

    ## People to reach

    {{personas_list}}

    ## Notes

    {{notes|none}}
  MD

  # Minimal RFC 4180 CSV parser (quotes, doubled quotes, embedded newlines).
  def self.parse_csv(text)
    rows = []
    row = []
    field = +''
    quoted = false
    i = 0
    text = text.sub(/\A﻿/, '')
    while i < text.length
      c = text[i]
      if quoted
        if c == '"'
          if text[i + 1] == '"'
            field << '"'
            i += 1
          else
            quoted = false
          end
        else
          field << c
        end
      elsif c == '"'
        quoted = true
      elsif c == ','
        row << field
        field = +''
      elsif c == "\n" || c == "\r"
        i += 1 if c == "\r" && text[i + 1] == "\n"
        row << field
        rows << row unless row.all?(&:empty?)
        row = []
        field = +''
      else
        field << c
      end
      i += 1
    end
    unless field.empty? && row.empty?
      row << field
      rows << row
    end
    raise Error, 'CSV is empty' if rows.empty?
    header = rows.shift.map(&:strip)
    rows.map { |r| header.zip(r.map { |v| v.to_s.strip }).to_h }
  end

  def self.slug(s)
    out = s.to_s.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/\A-|-\z/, '')
    out.empty? ? 'account' : out
  end

  # "A:VP Security;B:Director AppSec" -> list items. Plain "VP Security;Director" also works.
  def self.personas_list(raw)
    items = raw.to_s.split(';').map(&:strip).reject(&:empty?)
    return '_none recorded_' if items.empty?
    items.map do |it|
      tier, role = it.split(':', 2)
      role ? "- Persona #{tier.strip}: #{role.strip}" : "- #{it}"
    end.join("\n")
  end

  def self.render(template, rec)
    vals = rec.merge('personas_list' => personas_list(rec['personas']))
    template.gsub(/\{\{\s*([a-z_0-9]+)(?:\|([^}]*))?\s*\}\}/i) do
      v = vals[$1].to_s.strip
      v.empty? ? ($2 || '').strip : v
    end
  end

  # Returns problems for one record. +required+ is a list of column names that must be non-empty.
  def self.problems(rec, required:, stale_days: nil, today: Date.today)
    out = required.select { |k| rec[k].to_s.strip.empty? }.map { |k| "missing #{k}" }
    if stale_days && !rec['signal_date'].to_s.empty?
      begin
        age = (today - Date.iso8601(rec['signal_date'])).to_i
        out << "signal is #{age} days old (limit #{stale_days})" if age > stale_days
        out << 'signal date is in the future' if age < 0
      rescue ArgumentError
        out << "signal_date #{rec['signal_date'].inspect} is not YYYY-MM-DD"
      end
    end
    out
  end

  # Writes briefs + INDEX.md into +outdir+. Returns a result hash.
  def self.build(records, outdir:, template: DEFAULT_TEMPLATE, required: %w[account why_now], stale_days: nil, today: Date.today)
    FileUtils.mkdir_p(outdir)
    used = {}
    written = []
    skipped = []
    records.each do |rec|
      probs = problems(rec, required: required, stale_days: stale_days, today: today)
      if rec['account'].to_s.empty?
        skipped << ['(no account name)', probs]
        next
      end
      unless probs.empty?
        skipped << [rec['account'], probs]
        next
      end
      base = slug(rec['account'])
      name = base
      n = 2
      while used[name]
        name = "#{base}-#{n}"
        n += 1
      end
      used[name] = true
      File.write(File.join(outdir, "#{name}.md"), render(template, rec))
      written << [name, rec]
    end
    File.write(File.join(outdir, 'INDEX.md'), index(written, skipped))
    { written: written.size, skipped: skipped }
  end

  def self.index(written, skipped)
    lines = ["# Account briefs", '', "#{written.size} written, #{skipped.size} skipped.", '']
    by_tier = written.group_by { |_, r| r['tier'].to_s.empty? ? 'unassigned' : r['tier'] }
    by_tier.keys.sort.each do |t|
      lines << "## Tier: #{t}" << ''
      by_tier[t].each { |name, r| lines << "- [#{r['account']}](#{name}.md)" + (r['current_vendor'].to_s.empty? ? '' : " (using #{r['current_vendor']})") }
      lines << ''
    end
    vendors = written.map { |_, r| r['current_vendor'].to_s }.reject(&:empty?).tally
    unless vendors.empty?
      lines << '## Accounts per current vendor' << ''
      vendors.sort_by { |v, c| [-c, v] }.each { |v, c| lines << "- #{v}: #{c}" }
      lines << ''
    end
    unless skipped.empty?
      lines << '## Skipped' << ''
      skipped.each { |a, p| lines << "- #{a}: #{p.join('; ')}" }
      lines << ''
    end
    lines.join("\n")
  end
end
