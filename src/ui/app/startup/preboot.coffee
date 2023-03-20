import api from '../../../api/index.js'
import { Time } from '../../../lib/index.js'
import { parse_url } from '../routing/url.coffee'

# Set the API config from environment vars.
api.configure({
	clientID: process.env.API_CLIENT_ID
	loggingEnabled: ((new URLSearchParams(location.search)).get('debug') ? process.env.API_LOGGING_ENABLED) in ['TRUE', 'true', '1']
	redirectURI: process.env.API_REDIRECT_URI
})

# If a login attempt was started by a prior instance of the application, finish it.
if api.hasPendingLogin()
	{ error, memoString: remembered_path } = api.finishPendingLogin()
	if error
		switch error.reason
			when 'no-matching-login-attempt' then alert("Login failed. The login process should be completed in a single window, without opening other windows.")
			when 'user-refused-login' then alert("Login failed. You didn't allow access to your account.")
			else alert("Login failed. We didn't expect it to fail in this way so we don't know why. Error message: #{error.reason || error.message}")
	history.replaceState(null, null, remembered_path ? '/')

# Parse the current route so we can start making network requests for critical path data ASAP.
route = parse_url(location)
if route.preload
	for id in route.preload
		api.preload(id)