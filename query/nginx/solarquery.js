var crypto = require('crypto');

var AUTH_SCHEME_PATTERN = /^(SolarNetworkWS|SNWS2)\b/;
var SNWS_V1_KEY_PATTERN = /^SolarNetworkWS\s+([^:]+):/;
var SNWS_V2_KEY_PATTERN = /Credential=([^,]+)(?:,|$)/;

function addAuthorization(request, digest) {
	var header = request.headersIn['Authorization'],
		match, 
		scheme;
	
	if ( !header ) {
		return;
	}

	match = header.match(AUTH_SCHEME_PATTERN);
	if ( !match ) {
		return;
	}
	scheme = match[1];
	
	if ( "SNWS2" == scheme ) {
		match = header.match(SNWS_V2_KEY_PATTERN);
	} else {
		match = header.match(SNWS_V1_KEY_PATTERN);
	}
	if ( match ) {
		request.log('Auth = ' +match[1]);
		digest.update(match[1]);
		digest.update('@');
	}
}

function addQueryParam(request, digest, first, key, val) {
	if ( first ) {
		digest.update('?');
		first = false;
	} else {
		digest.update('&');
	}
	request.log('Query param ' +key +' = ' +decodeURIComponent(val));
	digest.update(key);
	digest.update('=');
	digest.update(decodeURIComponent(val));
	return first;
}

function addNormalizedQueryParameters(request, digest) {
	var keys = [],
		len,
		i,
		j,
		first = false,
		key,
		vals,
		valsLen,
		val;
		
	for ( key in request.args ) {
		keys.push(key);
	}
	len = keys.length;
	if ( len < 1 ) {
		return;
	}
	
	keys.sort();
	for ( i = 0; i < len; i += 1 ) {
		key = keys[i];
		vals = request.args[key];
		if ( vals ) {
			if ( Array.isArray(vals) ) {
				for ( j = 0, valsLen = vals.length; j < valsLen; j += 1 ) {
					val = vals[j];
					first = addQueryParam(request, digest, first, key, val);
				}
			} else {
				first = addQueryParam(request, digest, first, key, vals);
			}
		}
	}
}

function addNormalizedAccept(request, digest) {
	var header = request.headersIn['Accept'],
		match;
	if ( !header ) {
		return;
	}
	
	request.log('Accept = ' +header);
	
	if ( header.match(/application\/json/i) ) {
		digest.update('+json');
	} else if ( header.match(/text\/csv/i) ) {
		digest.update('+csv');
	} else if ( header.match(/text\/xml/i) ) {
		digest.update('+xml')
	} else {
		match = header.match(/(\w+)\/([^,]+)/);
		if ( match ) {
			digest.update('+');
			digest.update(match[1]);
			digest.update('/');
			digest.update(match[2]);
		}
	}
}

function addNormalizedAcceptEncoding(request, digest) {
	var header = request.headersIn['Accept-Encoding'],
		enc;
	if ( !header ) {
		return;
	}
	
	// assume server prefers br, then gzip
	if ( header.search(/\bbr\b/) >= 0 ) {
		enc = '>br';
	} else if ( header.search(/\bgzip\b/) >= 0 ) {
		enc = '>gzip';
	}
	if ( enc ) {
		request.log('Accept-Encoding = ' +enc);
		digest.update(enc);
	}
}

function keyForRequest(request) {
	var digest = crypto.createHash('md5');
	addAuthorization(request, digest);
	digest.update(request.method);
	request.log('URI = ' +request.uri);
	digest.update(request.uri);
	addNormalizedQueryParameters(request, digest);
	addNormalizedAccept(request, digest);
	addNormalizedAcceptEncoding(request, digest);
	var key = digest.digest();
	request.log('Key = ' +key.toString('hex'));
	return key;
}