# encoding: utf-8
# require 'pry'

class RenameImpactOnMetrics < Diggit::Analysis

	def delta_metrics(release, detect_renames)
		authors = Hash.new { |hash, key| hash[key] = Set.new }
		number_of_changes = Hash.new { |hash, key| hash[key] = 0 }
		code_churn = Hash.new { |hash, key| hash[key] = 0 }

		release_files = Set.new
		@repo.tags[release['v1']].target.tree.walk_blobs do |root, entry|
			unless @repo.lookup(entry[:oid]).binary?
				release_files << "#{root}#{entry[:name]}"
			end
		end
		release_files.each do |f|
			authors[f]
			number_of_changes[f]
			code_churn[f]
		end


		renames = Hash.new

		walker = Rugged::Walker.new(@repo)
		walker.sorting(Rugged::SORT_DATE | Rugged::SORT_TOPO | Rugged::SORT_REVERSE)

		walker.push(@repo.tags[release['v1']].target)
		walker.hide(@repo.tags[release['v0']].target) unless release['v0'].nil?
		walker.each do |commit|

			commit.parents.each do |parent|
				diff = parent.diff(commit)
				diff.find_similar! if detect_renames #activates rename detection
				diff.each do |patch|
					unless patch.delta.status == :deleted
						f = patch.delta.new_file[:path]

						if detect_renames
							if patch.delta.status == :renamed
								renames[patch.delta.old_file[:path]] = f
							end

							if renames.has_key? f
								f = renames[f]
							end
						end

						authors[f] << commit.author[:name]
						number_of_changes[f] = number_of_changes[f] + 1
						code_churn[f] = code_churn[f] + patch.stat[0] + patch.stat[1]
					end
				end
			end
		end
		number_of_authors = Hash.new
		authors.each { |key,value| number_of_authors[key] = value.size}
		return {:number_of_authors => number_of_authors, :number_of_changes => number_of_changes, :code_churn => code_churn}
	end

	def run
		releases = @addons[:db].db['releases'].find(:source => @source)
		releases.each do |r|
			metrics_rename = delta_metrics(r, true)
			metric_no_rename = delta_metrics(r, true)
			@addons[:db].db['delta_metrics'].insert({source:@source, release:r, metrics_rename:metrics_rename, metric_no_rename:metric_no_rename})
		end
	end

	def clean
		@addons[:db].db['delta_metrics'].remove({source:@source})
	end

end