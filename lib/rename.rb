# encoding: utf-8

class RenameAnalysis < Diggit::Analysis
	class Rename
		attr_reader :commit_oid
		attr_reader :commit_message
		attr_reader :old_path
		attr_reader :old_file_oid
		attr_reader :new_path
		attr_reader :new_file_oid

		def initialize(commit_oid, commit_message, old_file_oid, old_path, new_file_oid, new_path)
			@commit_oid = commit_oid
			@commit_message = commit_message
			@old_path = old_path
			@old_file_oid = old_file_oid
			@new_path = new_path
			@new_file_oid = new_file_oid
		end

		def to_bson
			return {commit_oid:@commit_oid,commit_message:@commit_message,old_path:@old_path,old_file_oid:@old_file_oid,new_path:@new_path,new_file_oid:new_file_oid}
		end
	end

	def export_renames
		@renames.each do |r|
			dir = '../renames/' + r.commit_oid + "_" + r.old_file_oid
			Dir.mkdir dir unless Dir.exists? dir

			File.open(dir + '/a.filename', 'w') { |f| f.puts r.old_path}
			File.open(dir + '/a', 'w') { |f| f.puts Rugged::Object.lookup(@repo, r.old_file_oid).content }
			File.open(dir + '/b.filename', 'w') { |f| f.puts r.new_path}
			File.open(dir + '/b', 'w') { |f| f.puts Rugged::Object.lookup(@repo, r.new_file_oid).content }
		end
	end


	def find_renames(release)
		walker = Rugged::Walker.new(@repo)
		walker.sorting(Rugged::SORT_DATE)
		puts release.inspect
		walker.push(@repo.tags[release['v1']].target)
		walker.hide(@repo.tags[release['v0']].target) unless release['v0'].nil?
		active_files = Set.new
		_renames = Array.new
		walker.each do |commit|
			commit.parents.each do |parent|
				diff = parent.diff(commit)
				diff.find_similar! #activates rename detection
				diff.each_delta do |delta|
					f = ''
					if delta.status == :deleted
						f = delta.old_file[:path]
					else
						f = delta.new_file[:path]
					end
					active_files << f
					if delta.status == :renamed
						rename = Rename.new(commit.oid, commit.message, delta.old_file[:oid],
							delta.old_file[:path], delta.new_file[:oid], delta.new_file[:path])
						_renames << rename
						@addons[:db].db['renames'].
							insert({release:release, source:@source, rename:rename.to_bson })
					end
				end
			end
		end
		@addons[:db].db['release-info'].
			insert({release:release, active_files:active_files.length, renamed_files:_renames.length})
		@renames = @renames + _renames
	end

	def run
		@renames = Array.new
		Dir.mkdir '../renames' unless Dir.exists? '../renames'

		releases = @addons[:db].db['releases'].find(:source => @source)
		releases.each { |r| find_renames(r) }
		export_renames
		processed_commits = Set.new
		File.open("../commit_messages", "a") { |f|
			@renames.each { |r|
				f.puts(r.commit_message) unless processed_commits.add?(r.commit_oid).nil?
			}
		}
	end
end
