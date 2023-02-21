// NOTE this code is for 0.4.0 <= njs via js_import

var messageCount = 0;
var clientId = '';

function getClientId(s) {
    return clientId;
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
    s.on('upload', function(data, flags) {
        if ( messageCount > 0 || data.length < 1 ) {
            return;
        }
        if ( messageCount < 1 ) {
            // upper 4 bits of byte 0 is packet type
            var packetType = data.charCodeAt(0) >> 4;

            if ( packetType === 1 ) {                  // CONNECT
                var lenPos = decodeRemainingLength(data, 1);

                // Support v3 & v4, which have different protocol names (MQIsdp vs MQTT)
                var protoNameLength = variableLengthStringLength(data, lenPos[1]);

                var versPos = lenPos[1]
                    + 2                                // variable length string length bytes
                    + protoNameLength;                 // proto name variable length string

                var vers = data.charCodeAt(versPos);

                var clientIdPos = versPos + 4;         // version byte, conn flags byte, timer bytes

                if ( vers > 4 ) {                      // v5 decode properties length and skip
                    var propsLenPos = decodeRemainingLength(data, clientIdPos);
                    clientIdPos = propsLenPos[1] + propsLenPos[0];
                }

                // set global var for future call to getClientId()
                clientId = extractVariableLengthString(data, clientIdPos);

                /*
                s.log('MQTT packet type = ' + packetType
                    + ', data = ' + data.slice(0, 32).toString('hex')
                    +', len = ' +data.slice(0,32).length
                    +', versPos = ' + versPos
                    +', vers = ' +vers
                    +', clientIdPos = ' +clientIdPos
                    +', clientIdLen = ' +clientId.length
                    );
                */

                // If client authentication then check certificate CN matches ClientId
                var certificateClientId = parseDnAttribute(s.variables.ssl_client_s_dn, 'UID');
                if ( !certificateClientId || certificateClientId != clientId ) {
                    s.log('Certificate client ID [' + certificateClientId
                        + '] does not match MQTT client ID [' +clientId +']');
                    s.deny();
                } else {
                    s.allow();
                }
            } else {
                s.log('Received unexpected MQTT packet type: ' + packetType);
            }
        }
        messageCount++;
    });
}

export default {discoverClientId, getClientId};
