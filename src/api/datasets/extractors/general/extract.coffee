import embeddable from './util/embeddable.coffee'
import DatasetID from '../../DatasetID.coffee'

# Separate and extract independent Reddit entities from raw API data.
# Primarily useful to parse Reddit's "Listing" and "Thing" data structures, and to flatten comment trees for store ingestion.
# All extractors return the same data structure. It is described below as it is constructed.
# NOTE: Contains side effects throughout (namely, input data modification).
export default extract = (rawData) ->
	result =
		main: null # The object specified by an API route.
		sub: [] # Objects contained in the same API response as the main objects, but which "belong" to a different API route.
	switch rawData.kind
		when 't1'
			# Comments in raw API data are structured as trees of comments containing other comments and various related objects. Our objective is to "de-link" these tree structures and subsequently identify comments entirely through direct ID reference.
			comment = rawData.data
			repliesListing = comment.replies?.data?.children
			if !Array.isArray(repliesListing) then repliesListing = []
			# Detect and process a "continue this thread" link in the comment's replies.
			if repliesListing.last?.kind is 'more' and repliesListing.last.depth >= 10
				repliesListing.pop()
				comment.deep_replies = true
			# Detect and process a "more comments" object in the comment's replies.
			if repliesListing.last?.kind is 'more'
				more = repliesListing.pop()
				comment.more_replies = more.data.children
			# Recursively extract all comments in this comment's reply tree.
			repliesListingDatasets = extract(comment.replies or []) # Sometimes Reddit sends an empty string instead of an empty array.
			# Set the IDs of the direct replies in place of the original objects.
			comment.replies = repliesListingDatasets.main.data
			result.main =
				id: new DatasetID('comment', rawData.data.id) # At the top level of the API response, we don't need the ID, as we already know which ID the data was requested for. However, identifying the ID becomes necessary when an object is nested.
				data: comment
			result.sub = repliesListingDatasets.sub
		when 't2'
			user = rawData.data
			result.main =
				id: new DatasetID('user_info', user.name)
				data: user
			if user.subreddit
				result.sub.push({
					id: new DatasetID('subreddit_info', user.subreddit.display_name)
					data: user.subreddit
					partial: true # Marks objects known to be an incomplete version of data from another API route.
				})
				delete user.subreddit
		when 't3'
			post = rawData.data
			# Normalize the URL - sometimes it is only given as a relative path.
			post.url = if post.url[0] == '/' then new URL("https://www.reddit.com#{post.url}") else new URL(post.url)
			# Detect the content format for the post.
			post.format = switch
				when post.media?.reddit_video or post.is_gallery or post.post_hint == 'image' or post.url.hostname == 'i.redd.it'
					'media'
				when post.tournament_data
					'prediction'
				when post.poll_data
					'poll'
				when post.is_self
					'self'
				when embeddable(post.url)
					'embed'
				else
					'link'
			# Organize all the media we might need for the post.
			# Any type of post can have media, not just media-format posts. For example, self posts can have inline images.
			# We try to maintain different representations of media where provided; for example, image previews of videos/GIFs.
			hosted_video_data = post.media?.reddit_video
			post.media = []
			if post.media_metadata and post.gallery_data and Array.isArray(post.gallery_data.items)
				post.media = post.gallery_data.items.map((item) ->
					mediaObject = { caption_text: item.caption, caption_url: item.outbound_url }
					data = post.media_metadata[item.media_id]
					if data.status isnt 'valid'
						mediaObject.image_url = null
					if data.s
						mediaObject.aspect_ratio = data.s.y / data.s.x
						if data.s.mp4
							mediaObject.video_url = data.s.mp4
							mediaObject.video_width = data.s.x
						else if data.s.gif
							mediaObject.gif_url = data.s.gif
							mediaObject.gif_width = data.s.x
						else
							mediaObject.image_url = data.s.u
							mediaObject['image_url_' + data.s.x] = data.s.u
					if data.p
						data.p.forEach((res) ->
							mediaObject['image_url_' + res.x] = res.u
						)
					return mediaObject
				)
			else if post.preview? and Array.isArray(post.preview.images)
				post.media = post.preview.images.map((item) ->
					mediaObject = {}
					if item.variants.mp4
						data = item.variants.mp4
						mediaObject.video_url = data.source.url
						mediaObject.video_width = data.source.width
					if item.variants.gif 
						data = item.variants.gif
						mediaObject.gif_url = data.source.url
						mediaObject.gif_width = data.source.width
					mediaObject.image_url = item.source.url
					mediaObject['image_url_' + item.source.width] = item.source.url
					item.resolutions.forEach((res) ->
						mediaObject['image_url_' + res.width] = res.url
					)
					mediaObject.aspect_ratio = item.source.height / item.source.width
					return mediaObject
				)
			else if post.url.hostname == 'i.redd.it'
				post.media[0] = if post.url.pathname.endsWith('gif') then { video_url: post.url } else { image_url: post.url }
			if hosted_video_data
				video = hosted_video_data
				post.media[0] =
					aspect_ratio: video.height / video.width
					video_url: video.fallback_url ? post.url
					video_width: video.width
					video_audio_url: if video.fallback_url and !video.is_gif then video.fallback_url.replaceAll(/DASH_[0-9]+/g, 'DASH_audio') else null
			if embeddable(post.url)
				post.media[0] = embeddable(post.url)
			# Collect the (possible) subreddit & crosspost-source objects, and the end post.
			if post.crosspost_parent_list?.length
				crosspost_parent_id = new DatasetID('post', post.crosspost_parent_list[0].id)
				result.sub.push({
					id: crosspost_parent_id
					data: extract({
						kind: 't3'
						data: post.crosspost_parent_list[0]
					})
					partial: true
				})
				post.crosspost_parent = crosspost_parent_id
				delete post.crosspost_parent_list
			if post.sr_detail
				result.sub.push({
					id: new DatasetID('subreddit_info', post.subreddit)
					data: post.sr_detail
					partial: true
				})
				delete post.sr_detail
			result.main =
				id: new DatasetID('post', rawData.data.id)
				data: post
				partial: true
		when 't4'
			result.main =
				id: new DatasetID('private_message', rawData.data.id)
				data: rawData.data
		when 't5'
			result.main =
				id: new DatasetID('subreddit_info', rawData.data.display_name)
				data: rawData.data
		when 'wikipage'
			wikipage = rawData.data
			revised_by_user_id = new DatasetID('user_info', wikipage.revision_by.data.name)
			result.sub.push({
				id: revised_by_user_id
				data: wikipage.revision_by.data
			})
			wikipage.revision_by = revised_by_user_id
			result.main =
				id: null
				data: wikipage
		when 'LabeledMulti'
			result.main =
				id: new DatasetID('multireddit_info', rawData.data.owner, rawData.data.name)
				data: rawData.data
		when 'Listing'
			listing = rawData.data.children
			if !Array.isArray(listing) then listing = []
			# If each top-level object in the listing is referenceable by ID, the primary data becomes simply an array of IDs.
			# If not, the primary data contains the full child objects.
			listingDatasets = listing.map((item) -> extract(item))
			childIds = listingDatasets.map(({ main }) -> main.id)
			if childIds.every((id) -> id?)
				result.main =
					id: null
					data: childIds
				result.sub = listingDatasets.flatMap(({ main, sub }) -> sub.concat(main))
			else
				result.main =
					id: null
					data: listingDatasets.map(({ main }) -> main.data)
				result.sub = listingDatasets.flatMap(({ sub }) -> sub)
		when 'LiveUpdate'
			result.main =
				id: null # NOTE: We'd like to assign these as "livethread_update", since live updates appear to have globally unique IDs. Unfortunately, there's no endpoint available to get an update solely by its ID (need thread ID as well), so assigning IDs here would break our data modeling assumptions.
				data: rawData.data
		when 'LiveUpdateEvent'
			result.main =
				id: new DatasetID('livethread_info', rawData.data.id)
				data: rawData.data
		when 'UserList'
			result.main =
				id: null
				data: rawData.data.children
		else
			if Array.isArray(rawData)
				# Essentially the same logic as for listings.
				arrayDatasets = rawData.map((child) -> extract(child))
				childIds = arrayDatasets.map(({ main }) -> main.id)
				if childIds.every((id) -> id?)
					result.main =
						id: null
						data: childIds
					result.sub = arrayDatasets.flatMap(({ main, sub }) -> sub.concat(main))
				else
					result.main =
						id: null
						data: arrayDatasets.map(({ main }) -> main.data)
					result.sub = arrayDatasets.flatMap(({ sub }) -> sub)
			else
				result.main =
					id: null
					data: rawData
	return result