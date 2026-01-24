#!/bin/bash
# Sonos Grouping API Test Script
# Tests the grouping/ungrouping functionality before integrating into the app

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "========================================"
echo "Sonos Grouping API Test Suite"
echo "========================================"
echo ""

# Function to get zone group topology
get_topology() {
    local ip=$1
    curl -s -X POST "http://${ip}:1400/ZoneGroupTopology/Control" \
        -H "Content-Type: text/xml; charset=utf-8" \
        -H "SOAPACTION: \"urn:schemas-upnp-org:service:ZoneGroupTopology:1#GetZoneGroupState\"" \
        -d '<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    <u:GetZoneGroupState xmlns:u="urn:schemas-upnp-org:service:ZoneGroupTopology:1"/>
  </s:Body>
</s:Envelope>'
}

# Function to parse and display groups
show_groups() {
    local ip=$1
    echo -e "${YELLOW}Current Groups:${NC}"
    get_topology "$ip" | sed 's/&lt;/</g; s/&gt;/>/g; s/&quot;/"/g; s/&amp;/\&/g' | \
        grep -oE '<ZoneGroup[^>]*Coordinator="[^"]*"' | \
        sed 's/<ZoneGroup.*Coordinator="/  Coordinator: /; s/"$//'
    echo ""
}

# Function to join a zone to a group
join_group() {
    local zone_ip=$1
    local coordinator_uid=$2
    
    echo -e "Joining ${zone_ip} to group ${coordinator_uid}..."
    
    local response=$(curl -s -X POST "http://${zone_ip}:1400/MediaRenderer/AVTransport/Control" \
        -H "Content-Type: text/xml; charset=utf-8" \
        -H "SOAPACTION: \"urn:schemas-upnp-org:service:AVTransport:1#SetAVTransportURI\"" \
        -d "<?xml version=\"1.0\" encoding=\"utf-8\"?>
<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\">
  <s:Body>
    <u:SetAVTransportURI xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\">
      <InstanceID>0</InstanceID>
      <CurrentURI>x-rincon:${coordinator_uid}</CurrentURI>
      <CurrentURIMetaData></CurrentURIMetaData>
    </u:SetAVTransportURI>
  </s:Body>
</s:Envelope>")
    
    if echo "$response" | grep -q "SetAVTransportURIResponse"; then
        echo -e "${GREEN}  SUCCESS${NC}"
        return 0
    else
        echo -e "${RED}  FAILED${NC}"
        echo "$response" | grep -oE '<faultstring>[^<]*</faultstring>|<errorCode>[^<]*</errorCode>' || echo "$response"
        return 1
    fi
}

# Function to make a zone standalone (ungroup)
ungroup() {
    local zone_ip=$1
    
    echo -e "Making ${zone_ip} standalone..."
    
    local response=$(curl -s -X POST "http://${zone_ip}:1400/MediaRenderer/AVTransport/Control" \
        -H "Content-Type: text/xml; charset=utf-8" \
        -H "SOAPACTION: \"urn:schemas-upnp-org:service:AVTransport:1#BecomeCoordinatorOfStandaloneGroup\"" \
        -d '<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    <u:BecomeCoordinatorOfStandaloneGroup xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
      <InstanceID>0</InstanceID>
    </u:BecomeCoordinatorOfStandaloneGroup>
  </s:Body>
</s:Envelope>')
    
    if echo "$response" | grep -q "BecomeCoordinatorOfStandaloneGroupResponse"; then
        echo -e "${GREEN}  SUCCESS${NC}"
        local new_group=$(echo "$response" | grep -oE '<NewGroupID>[^<]*</NewGroupID>' | sed 's/<[^>]*>//g')
        echo "  New group ID: $new_group"
        return 0
    else
        echo -e "${RED}  FAILED${NC}"
        echo "$response" | grep -oE '<faultstring>[^<]*</faultstring>|<errorCode>[^<]*</errorCode>|<errorDescription>[^<]*</errorDescription>' || echo "$response"
        return 1
    fi
}

# Function to get transport info (what's playing)
get_transport_info() {
    local ip=$1
    
    local response=$(curl -s -X POST "http://${ip}:1400/MediaRenderer/AVTransport/Control" \
        -H "Content-Type: text/xml; charset=utf-8" \
        -H "SOAPACTION: \"urn:schemas-upnp-org:service:AVTransport:1#GetTransportInfo\"" \
        -d '<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    <u:GetTransportInfo xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
      <InstanceID>0</InstanceID>
    </u:GetTransportInfo>
  </s:Body>
</s:Envelope>')
    
    local state=$(echo "$response" | grep -oE '<CurrentTransportState>[^<]*</CurrentTransportState>' | sed 's/<[^>]*>//g')
    echo "$state"
}

# Function to discover zones from topology
discover_zones() {
    local ip=$1
    echo -e "${YELLOW}Discovering zones...${NC}"
    
    local topology=$(get_topology "$ip")
    local decoded=$(echo "$topology" | sed 's/&lt;/</g; s/&gt;/>/g; s/&quot;/"/g; s/&amp;/\&/g')
    
    # Extract zone members (excluding Invisible ones for grouping)
    echo "$decoded" | grep -oE '<(ZoneGroupMember|Satellite)[^>]*UUID="[^"]*"[^>]*Location="http://[^"]*"[^>]*ZoneName="[^"]*"[^>]*' | while read -r line; do
        local uuid=$(echo "$line" | grep -oE 'UUID="[^"]*"' | sed 's/UUID="//; s/"$//')
        local location=$(echo "$line" | grep -oE 'Location="[^"]*"' | sed 's/Location="//; s/"$//')
        local name=$(echo "$line" | grep -oE 'ZoneName="[^"]*"' | sed 's/ZoneName="//; s/"$//')
        local ip=$(echo "$location" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')
        local invisible=$(echo "$line" | grep -o 'Invisible="1"' || true)
        local htsat=$(echo "$line" | grep -oE 'HTSatChanMapSet="[^"]*"' | sed 's/HTSatChanMapSet="//; s/"$//' || true)
        
        if [ -n "$invisible" ]; then
            echo "  [BONDED] $name ($ip) - UUID: $uuid"
        elif [ -n "$htsat" ]; then
            # Check if this is main unit or satellite
            if echo "$htsat" | grep -qE "${uuid}:(LF|RF)"; then
                echo "  [MAIN]   $name ($ip) - UUID: $uuid - Controls surround"
            fi
        else
            echo "  [ZONE]   $name ($ip) - UUID: $uuid"
        fi
    done
    echo ""
}

# ========================================
# TEST CASES
# ========================================

# Known IPs from discovery (update these for your network)
DINING_ROOM_IP="192.168.0.211"      # Dining Room (stereo pair coordinator)
LIVING_ROOM_IP="192.168.0.233"      # Living Room (surround main unit/soundbar)
TP_IP="192.168.0.215"               # tp (standalone)

# Known UIDs (from topology)
DINING_ROOM_UID="RINCON_38420B946FB001400"
LIVING_ROOM_UID="RINCON_38420B4D142701400"
TP_UID="RINCON_347E5CDD112C01400"

echo "Test Configuration:"
echo "  Dining Room: $DINING_ROOM_IP (UID: $DINING_ROOM_UID)"
echo "  Living Room: $LIVING_ROOM_IP (UID: $LIVING_ROOM_UID)"
echo "  tp:          $TP_IP (UID: $TP_UID)"
echo ""

# Discover current state
discover_zones "$DINING_ROOM_IP"
show_groups "$DINING_ROOM_IP"

# ----------------------------------------
echo "========================================"
echo "TEST 1: Ungroup Living Room (surround system)"
echo "========================================"
echo "This tests ungrouping a surround system from a group."
echo "Expected: Living Room becomes standalone, audio stops on Living Room."
echo ""

echo "Before state:"
echo "  Living Room transport: $(get_transport_info $LIVING_ROOM_IP)"
echo "  Dining Room transport: $(get_transport_info $DINING_ROOM_IP)"
echo ""

if ungroup "$LIVING_ROOM_IP"; then
    sleep 2  # Wait for topology to update
    echo ""
    echo "After state:"
    echo "  Living Room transport: $(get_transport_info $LIVING_ROOM_IP)"
    echo "  Dining Room transport: $(get_transport_info $DINING_ROOM_IP)"
    show_groups "$DINING_ROOM_IP"
else
    echo -e "${RED}TEST 1 FAILED${NC}"
    exit 1
fi

# ----------------------------------------
echo "========================================"
echo "TEST 2: Re-join Living Room to Dining Room"
echo "========================================"
echo "This tests joining a surround system to another group."
echo "Expected: Living Room joins Dining Room, plays Dining Room's audio."
echo ""

if join_group "$LIVING_ROOM_IP" "$DINING_ROOM_UID"; then
    sleep 2
    echo ""
    echo "After state:"
    echo "  Living Room transport: $(get_transport_info $LIVING_ROOM_IP)"
    show_groups "$DINING_ROOM_IP"
else
    echo -e "${RED}TEST 2 FAILED${NC}"
    exit 1
fi

# ----------------------------------------
echo "========================================"
echo "TEST 3: Ungroup tp (standalone speaker)"
echo "========================================"
echo "Testing that ungrouping an already-standalone speaker doesn't fail."
echo ""

if ungroup "$TP_IP"; then
    echo -e "${GREEN}TEST 3 PASSED${NC} - Standalone speaker handled correctly"
else
    echo -e "${RED}TEST 3 FAILED${NC}"
    exit 1
fi

# ----------------------------------------
echo "========================================"
echo "TEST 4: Join tp to Living Room"  
echo "========================================"
echo "Testing joining a standalone speaker to a surround system."
echo ""

# First make sure Living Room is standalone
ungroup "$LIVING_ROOM_IP"
sleep 1

if join_group "$TP_IP" "$LIVING_ROOM_UID"; then
    sleep 2
    show_groups "$DINING_ROOM_IP"
    echo -e "${GREEN}TEST 4 PASSED${NC}"
else
    echo -e "${RED}TEST 4 FAILED${NC}"
    exit 1
fi

# Cleanup - restore original grouping
echo "========================================"
echo "Restoring original grouping..."
echo "========================================"
ungroup "$TP_IP"
sleep 1
join_group "$LIVING_ROOM_IP" "$DINING_ROOM_UID"
sleep 1
show_groups "$DINING_ROOM_IP"

echo ""
echo -e "${GREEN}========================================"
echo "ALL TESTS PASSED"
echo "========================================${NC}"
echo ""
echo "Summary of what was tested:"
echo "  1. Ungrouping a surround system (main unit controls all satellites)"
echo "  2. Joining a surround system to another group"
echo "  3. Ungrouping an already-standalone speaker (no error)"
echo "  4. Joining a standalone speaker to a surround system"
echo ""
echo "Key findings for app implementation:"
echo "  - Always send commands to the MAIN UNIT (soundbar) for surround systems"
echo "  - Satellites (sub, rears) are controlled automatically"
echo "  - Stereo pairs: send commands to the NON-Invisible speaker"
echo "  - After ungrouping, the speaker's transport state changes to STOPPED"
echo "  - After joining, the speaker inherits the coordinator's audio"
