# encoding: utf-8

class ReleasesExtraction < Diggit::Analysis

	class VersionTag
		include Comparable

		attr :numbers
		attr :name
		attr :qualifier

		def initialize(tag)
			@name = tag.name
			m = /((?:[0-9]+[\._])*[0-9]+)(?:[\._\-]?([a-zA-Z0-9\-_]+))?/.match(tag.name)
			@numbers = Array.new
			m[1].split(/[\._]/).each { |n| @numbers << n.to_i }
			@qualifier = m[2]
		end

		def <=>(other)
			len = [@numbers.length, other.numbers.length].min
			0.upto(len - 1) do |n|
				cmp = @numbers[n] <=> other.numbers[n]
				return cmp unless cmp == 0
			end
			return @numbers.length <=> other.numbers.length
		end

		def compare_major(other)
			unless @numbers.empty? || other.numbers.empty?
				return @numbers[0] <=> other.numbers[0]
			end
			return 0
		end

		def compare_minor(other)
			unless @numbers.length < 2 || other.numbers.length < 2
				return @numbers[1] <=> other.numbers[1]
			end
			return 0
		end

		def final?
			return qualifier.nil? || qualifier.casecmp('final') == 0
		end
	end

	def extract_releases(tags)
		version_tags = Array.new
		tags.each do |t|
			unless /^((!backups)*)[a-zA-Z_-]*([0-9]+[\._])*[0-9]+/.match(t.name).nil?
				version_tags << VersionTag.new(t)
			end
		end
		version_tags.sort!
		releases = Array.new

		v_prev = nil
		version_tags.each do |v|
			if v.final? && (v_prev.nil? || v.compare_major(v_prev) != 0 || v.compare_minor(v_prev) != 0)
				releases << [v_prev, v]
				v_prev = v
			end
		end

		return releases
	end

	def run
		releases = extract_releases(@repo.tags)
		db = @addons[:db].db['releases']
		releases.each_with_index do |r, idx|
			v0 = r[0].nil? ? nil : r[0].name
			db.insert({source:@source, v0:v0, v1:r[1].name, idx:idx})
		end
	end

	def clean
		@addons[:db].db['releases'].remove({source:@source})
	end

end
