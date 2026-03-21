require "rails_helper"

RSpec.describe Blog::VttCleanerService do
  describe ".call" do
    it "odstraní WEBVTT header a timestamp řádky" do
      raw = <<~VTT
        WEBVTT

        00:00:01.000 --> 00:00:04.000
        Hello world

        00:00:04.000 --> 00:00:07.000
        How are you
      VTT

      result = described_class.call(raw)
      expect(result).to eq("Hello world How are you")
    end

    it "odstraní HTML tagy z textu" do
      raw = <<~VTT
        WEBVTT

        00:00:01.000 --> 00:00:03.000
        <c.colorCCCCCC>BBQ tips</c>
      VTT

      result = described_class.call(raw)
      expect(result).to eq("BBQ tips")
    end

    it "deduplikuje overlapping rolling captions" do
      raw = <<~VTT
        WEBVTT

        00:00:01.000 --> 00:00:03.000
        smoke the brisket low

        00:00:02.000 --> 00:00:04.000
        low and slow for

        00:00:03.000 --> 00:00:05.000
        slow for twelve hours
      VTT

      result = described_class.call(raw)
      expect(result).to eq("smoke the brisket low and slow for twelve hours")
    end

    it "vrátí prázdný string pro prázdný vstup" do
      expect(described_class.call("")).to eq("")
    end
  end

  describe ".longest_suffix_prefix_overlap" do
    it "nalezne overlap" do
      expect(described_class.longest_suffix_prefix_overlap("hello world", "world today")).to eq(5)
    end

    it "vrátí 0 pokud overlap neexistuje" do
      expect(described_class.longest_suffix_prefix_overlap("hello", "world")).to eq(0)
    end
  end
end
