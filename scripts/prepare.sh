#!/bin/bash

set +e  # Exit on any error

API_URL="$1"
API_KEY="$2"
SECRET_KEY="$3"
TEST_PLATFORM="$4"
DATA_PAYLOAD="$5"

GRID_NAME="github_actions_grid_${TEST_PLATFORM}"

# Log in and get session key
LOGIN_RESPONSE=$(curl -s -X POST "$API_URL/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"apiKey\":\"$API_KEY\", \"secretKey\":\"$SECRET_KEY\"}")

SESSION_KEY=$(echo "$LOGIN_RESPONSE" | jq -r .sessionKey)

if [ -z "$SESSION_KEY" ] || [ "$SESSION_KEY" == "null" ]; then
  echo "Error: Failed to obtain session key. API response: $LOGIN_RESPONSE"
  exit 1
fi

echo "Logged in, session key obtained."

# Get list of grids
GRID_RESPONSE=$(curl -s -X GET "$API_URL/api/grids" -H "Authorization: $SESSION_KEY")

echo "Raw GRID_RESPONSE: $GRID_RESPONSE"  # Debugging output

# Ensure the response is a JSON array before parsing
if ! echo "$GRID_RESPONSE" | jq -e 'type == "array"' > /dev/null; then
  echo "Error: Unexpected API response format. Expected JSON array but got: $GRID_RESPONSE"
  exit 1
fi

GRID_ID=$(echo "$GRID_RESPONSE" | jq -r ".[] | select(.name == \"$GRID_NAME\") | .id")

if [ -z "$GRID_ID" ] || [ "$GRID_ID" == "null" ]; then
  echo "Grid $GRID_NAME does not exist, creating it..."
  IS_PLAYWRIGHT=false
  if [ "$TEST_PLATFORM" == "PLAYWRIGHT" ]; then
    IS_PLAYWRIGHT=true
  fi

  CREATE_RESPONSE=$(curl -s -X POST "$API_URL/api/grids" \
    -H "Authorization: $SESSION_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"$GRID_NAME\", \"localTesting\":false, \"isPlaywright\":$IS_PLAYWRIGHT}")
  
  GRID_ID=$(echo "$CREATE_RESPONSE" | jq -r .gridId)
  
  if [ -z "$GRID_ID" ] || [ "$GRID_ID" == "null" ]; then
    echo "Error: Failed to create grid. API response: $CREATE_RESPONSE"
    exit 1
  fi
  
  echo "Created grid with ID: $GRID_ID"
else
  echo "Using existing grid with ID: $GRID_ID"
fi

# Export GRID_ID to GitHub Actions environment
echo "GRID_ID=$GRID_ID" >> "$GITHUB_ENV"

# Poll until grid is READY or RUNNING
while :; do
  GRID_STATUS_RESPONSE=$(curl -s -X GET "$API_URL/api/grids/$GRID_ID" -H "Authorization: $SESSION_KEY")
  GRID_STATUS=$(echo "$GRID_STATUS_RESPONSE" | jq -r .status)
  PROXY_URL=$(echo "$GRID_STATUS_RESPONSE" | jq -r .proxyUrl)

  if [ -z "$GRID_STATUS" ] || [ "$GRID_STATUS" == "null" ]; then
    echo "Error: Failed to get grid status. API response: $GRID_STATUS_RESPONSE"
    exit 1
  fi

  if [ "$GRID_STATUS" == "RUNNING" ]; then
    echo "Grid is already running. Proxy URL: $PROXY_URL"
    echo "PROXY_URL=$PROXY_URL" >> "$GITHUB_ENV"
    
    # Debug: Check last exit code before exiting
    echo "Last command exit code before exit: $?"

    echo "Invoking exit 0"
    exit 0

    echo "This should NEVER be printed"  # If this prints, something is wrong
    
  elif [ "$GRID_STATUS" == "READY" ]; then
    echo "Grid is ready, starting nodes..."
    echo "Sending payload: $DATA_PAYLOAD"
    printf "Sending payload: $DATA_PAYLOAD"
    START_RESPONSE=$(curl -s -X POST "$API_URL/api/grids/$GRID_ID/nodes" \
      -H "Authorization: $SESSION_KEY" \
      -H "Content-Type: application/json" \
      -d "$DATA_PAYLOAD")
    
    # Check if the response is valid JSON and log it regardless of success or failure
    if ! echo "$START_RESPONSE" | jq empty > /dev/null 2>&1; then
      echo "Error: Failed to start nodes. API response: $START_RESPONSE"
      exit 1
    else
      echo "Success: Nodes started. API response: $START_RESPONSE"
    fi
  fi

  echo "Waiting for grid to be ready..."
  sleep 10
done
