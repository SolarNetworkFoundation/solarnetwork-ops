// NOTE this code is for njs < 0.2.4

var messageCount = 0;
var clientId = '';

function getClientId(s) {
    return clientId;
}

function hexEncode(str) {
    var hex,
        i,
        result = '';
    for ( i = 0; i < str.length; i += 1 ) {
        hex = str.charCodeAt(i).toString(16);
        if ( result.length > 0 ) {
            result += " ";
        }
        result += ('0'+hex).slice(-2);
    }
    return result
}

function parseDnAttribute(dn, att) {
    var regex = new RegExp('\\b' +att +'=([^,]+)', 'i'),
        match = regex.exec(dn);
    return (match ? match[1] : null);
}

function decodeRemainingLength(buffer, p) {
    var multiplier = 1,
        result = 0,
        b;
    do {
        b = buffer.charCodeAt(p);
        result += (b & 127) * multiplier;
        multiplier *= 128;
        p += 1;
    } while ( (b & 128) != 0 );
    // return result and next position in buffer
    return [result, p];
}

function variableLengthStringLength(buffer, p) {
    var msb = buffer.charCodeAt(p),
        lsb = buffer.charCodeAt(p + 1);
    return (msb << 8) | lsb;
}

function extractVariableLengthString(buffer, p) {
    var msb = buffer.charCodeAt(p),
        lsb = buffer.charCodeAt(p + 1),
        len = (msb << 8) | lsb,
        result = buffer.substr(p + 2, len);
    return result;
}

function discoverClientId(s) {
    if ( !s.fromUpstream ) {
        if ( s.buffer.toString().length == 0  ) {
            return s.AGAIN;
        } else if ( messageCount < 1 ) {
            // upper 4 bits of byte 0 is packet type
            var packetType = s.buffer.charCodeAt(0) >> 4;

            /*
            s.log('MQTT packet type = ' + packetType
                + ', buffer(32) = ' + hexEncode(s.buffer.slice(0, 32))
                +', len = ' +s.buffer.slice(0,32).length
                + ', s = ' +s.buffer.slice(0,32));
            */

            if ( packetType === 1 ) { // CONNECT
                // Calculate remaining length with variable encoding scheme
                var lenPos = decodeRemainingLength(s.buffer, 1);

                // Support v3 & v4, which have different protocol names (MQIsdp vs MQTT)
                var protoNameLength = variableLengthStringLength(s.buffer, lenPos[1]);

                var clientIdPos = lenPos[1]
                    + 2                 // variable length string length bytes
                    + protoNameLength   // proto name variable length string
                    + 4;                // version byte, conn flags byte, timer bytes

                // CONNECT variable length header 10 bytes, client ID follows
                clientId = extractVariableLengthString(s.buffer, clientIdPos);

                // If client authentication then check certificate CN matches ClientId
                var certificateClientId = parseDnAttribute(s.variables.ssl_client_s_dn, 'UID');
                if ( certificateClientId && certificateClientId != clientId ) {
                    s.log('Certificate client ID [' + certificateClientId
                        + '] does not match MQTT client ID [' +clientId +']');
                    return s.ERROR;
                }
            } else {
                s.log('Received unexpected MQTT packet type: ' + packetType);
            }
        }
        messageCount++;
    }
    return s.OK;
}
