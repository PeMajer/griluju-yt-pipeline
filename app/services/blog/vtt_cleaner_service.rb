module Blog
  # Čistí VTT přepis od tagů a odstraňuje duplicity způsobené rolling captions
  # (YouTube auto-captions mají velký overlap mezi sousedními bloky).
  class VttCleanerService
    def self.call(raw_vtt)
      lines   = strip_vtt(raw_vtt)
      deduped = deduplicate(lines)
      deduped.join(" ").gsub(/\s{2,}/, " ").strip
    end

    def self.strip_vtt(raw_vtt)
      raw_vtt
        .lines
        .reject { |l| l =~ /^WEBVTT|^\d{2}:\d{2}:\d{2}\.\d{3} -->|^\s*$/ }
        .map { |l| l.gsub(/<[^>]+>/, "").strip }
        .reject(&:empty?)
    end

    def self.deduplicate(lines)
      return lines if lines.size < 2

      result = [ lines.first ]
      lines.each_cons(2) do |prev, curr|
        overlap  = longest_suffix_prefix_overlap(prev, curr)
        new_part = curr[overlap..].strip
        result << new_part unless new_part.empty?
      end
      result
    end

    def self.longest_suffix_prefix_overlap(a, b)
      max_check = [ a.length, b.length ].min
      max_check.downto(1) do |len|
        return len if a.end_with?(b[0, len])
      end
      0
    end
  end
end
