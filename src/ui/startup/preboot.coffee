import api from '../../api/index.js'
import { parse_url } from '../url/index.js'

# Set the API config from environment vars and query params.
query = new URLSearchParams(location.search)
clientID = process.env.API_CLIENT_ID
debug = String(query.get('debug') or query.get('log') or process.env.API_DEBUG).toLowerCase() in ['1', 'true']
redirectURI = process.env.API_REDIRECT_URI
api.configure({
	clientID,
	debug,
	redirectURI,
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
		api.load(id)