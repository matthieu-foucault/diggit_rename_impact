# encoding: utf-8
require 'pry'

class RenameImpactOnMetrics < Diggit::Analysis

	COMMIT_WINDOW_SIZE = 500

	def delta_metrics(detect_renames)
		authors = Hash.new { |hash, key| hash[key] = Set.new }
		number_of_changes = Hash.new { |hash, key| hash[key] = 0 }
		code_churn = Hash.new { |hash, key| hash[key] = 0 }

		release_files = Set.new
		@last_commit.tree.walk_blobs do |root, entry|
			unless @repo.lookup(entry[:oid]).binary?
				release_files << "#{root}#{entry[:name]}"
			end
		end
		# release_files.each do |f|
		# 	authors[f]
		# 	number_of_changes[f]
		# 	code_churn[f]
		# end
		renames = {}

		walker = Rugged::Walker.new(@repo)
		walker.sorting(Rugged::SORT_DATE | Rugged::SORT_TOPO)
		walker.push(@last_commit)

		num_commits = 0
		walker.each do |commit|
			if commit.parents.size == 1
				num_commits += 1
				parent = commit.parents[0]
				diff = parent.diff(commit)
				diff.find_similar! if detect_renames # activates rename detection
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
						if release_files.include? f
							authors[f] << commit.author[:name]
							number_of_changes[f] = number_of_changes[f] + 1
							code_churn[f] = code_churn[f] + patch.stat[0] + patch.stat[1]
						end
					end
				end
			end
			if num_commits == COMMIT_WINDOW_SIZE
				@last_commit_tmp = commit
				break
			end
		end
		throw :done if num_commits < COMMIT_WINDOW_SIZE

		number_of_authors = {}
		authors.each { |key, value| number_of_authors[key] = value.size }
		return {:number_of_authors => number_of_authors, :number_of_changes => number_of_changes, :code_churn => code_churn}
	end

	def run
		@last_commit = @repo.head.target
		catch (:done) do
			idx = 0
			while true
				metrics_rename = delta_metrics(true)
				metric_no_rename = delta_metrics(false)
				@addons[:db].db['delta_metrics'].insert({source: @source, idx: idx, metrics_rename: metrics_rename, metric_no_rename: metric_no_rename })
				@last_commit = @last_commit_tmp
				idx = idx + 1
			end

		end
	end

	def clean
		@addons[:db].db['delta_metrics'].remove({source:@source})
	end

end