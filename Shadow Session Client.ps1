Add-Type -AssemblyName System.Windows.Forms

# --- Load Server List ---
# Define the path to the servers.txt file in the same directory as the script
$serversFilePath = Join-Path -Path (Split-Path -Parent $MyInvocation.MyCommand.Definition) -ChildPath "servers.txt"

# Initialize server list
$serverList = @()

# Check if the servers.txt file exists and read it
if (Test-Path $serversFilePath) {
    $serverList = Get-Content -Path $serversFilePath | Where-Object { $_ -and $_.Trim() -ne "" } # Filter out empty lines
}

# If the file doesn't exist or is empty, default to the original hardcoded value
if ($serverList.Count -eq 0) {
    $serverList = @("192.168.88.1") # Default server if file is missing or empty
}
# --- End Load Server List ---

# Create the main form
$form = New-Object System.Windows.Forms.Form
$form.Text = "Remote Desktop Shadowing"
$form.Width = 400
$form.Height = 420 # Slightly increased height for ComboBox
$form.StartPosition = "CenterScreen" # Optional: Center the form on screen

# Create a label and ComboBox for the server selection
$serverLabel = New-Object System.Windows.Forms.Label
$serverLabel.Text = "Select Server:"
$serverLabel.Location = New-Object System.Drawing.Point(10, 10)
$serverLabel.AutoSize = $true
$form.Controls.Add($serverLabel)

$serverComboBox = New-Object System.Windows.Forms.ComboBox
$serverComboBox.Location = New-Object System.Drawing.Point(10, 30)
$serverComboBox.Width = 200
$serverComboBox.DropDownStyle = "DropDownList" # Makes it non-editable

# Populate the ComboBox with servers from the list
foreach ($server in $serverList) {
    [void]$serverComboBox.Items.Add($server.Trim())
}
# Select the first server by default if available
if ($serverComboBox.Items.Count -gt 0) {
    $serverComboBox.SelectedIndex = 0
}
$form.Controls.Add($serverComboBox)

# Create a button to get sessions
$getSessionsButton = New-Object System.Windows.Forms.Button
$getSessionsButton.Text = "Get Sessions"
$getSessionsButton.Location = New-Object System.Drawing.Point(10, 60) # Position adjusted
$getSessionsButton.Width = 100 # Optional: Set a specific width
$getSessionsButton.Add_Click({
    # Use the selected server from the ComboBox
    $SelectedServer = $serverComboBox.SelectedItem
    if ([string]::IsNullOrWhiteSpace($SelectedServer)) {
        [System.Windows.Forms.MessageBox]::Show("Please select a server.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }

    # $result = qwinsta /server:$ComputerName 2>&1
    $result = qwinsta /server:$SelectedServer 2>&1

    # Clear the previous results
    $sessionsListBox.Items.Clear()

    if ($result -match "No user exists") {
        [System.Windows.Forms.MessageBox]::Show("No active sessions found on server '$SelectedServer'.", "Info", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        return
    }

    # Check if the command itself failed (e.g., server unreachable)
    if ($LASTEXITCODE -ne 0) {
         [System.Windows.Forms.MessageBox]::Show("Error retrieving sessions from '$SelectedServer'. Ensure the server is reachable and you have permissions. Error: $result", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
         return
    }


    # Process the results (skip header line)
    # Robust parsing: Handle potential variations in qwinsta output format
    $startIndex = 1
    if ($result.Count -gt 0 -and $result[0] -match "SESSIONNAME\s+USERNAME\s+ID\s+STATE\s+TYPE\s+DEVICE") {
        $startIndex = 1
    } elseif ($result.Count -gt 1 -and $result[1] -match "SESSIONNAME\s+USERNAME\s+ID\s+STATE\s+TYPE\s+DEVICE") {
         $startIndex = 2
    }

    try {
        for ($i = $startIndex; $i -lt $result.Count; $i++) {
            $line = $result[$i]
            # Skip empty lines or lines that are just whitespace
            if ([string]::IsNullOrWhiteSpace($line)) {
                continue
            }

            # Example line (positions can vary slightly):
            #  services                                    0  Disc
            # >rdp-tcp#0         Administrator              1  Active
            #  console                                     3  Conn
            # Assuming fixed-width format based on standard qwinsta output
            # Be cautious with Substring if the format isn't strictly fixed.

            # A more robust way is to use regex or split based on whitespace, but substring is used as in original
            # Let's try to parse more safely, checking length first

            # Basic check: line should be long enough
            if ($line.Length -lt 40) {
                continue # Skip lines that are too short to contain expected data
            }

            # Extract parts based on typical qwinsta output columns
            $sessionName = $line.Substring(0, [Math]::Min(18, $line.Length)).Trim()
            $usernameStart = 18
            $usernameLength = [Math]::Min(22, $line.Length - $usernameStart)
            if ($usernameLength -lt 0) { $usernameLength = 0 }
            $username = $line.Substring($usernameStart, $usernameLength).Trim()
            $idStart = 40
            $idLength = [Math]::Min(8, $line.Length - $idStart)
             if ($idLength -lt 0) { $idLength = 0 }
            $id = $line.Substring($idStart, $idLength).Trim()

            # Only add items where we found a username or session name that indicates a real session
            # (Sometimes 'services' or 'console' sessions appear without usernames)
            if (![string]::IsNullOrWhiteSpace($username) -or $sessionName -match "rdp-tcp|console") {
                 # Create a display string
                 $displayString = ""
                 if (![string]::IsNullOrWhiteSpace($username)) {
                    $displayString = "$username - $id"
                 } else {
                    $displayString = "$sessionName - $id"
                 }
                 $sessionsListBox.Items.Add($displayString)
            }
        }
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Error parsing session data from '$SelectedServer'. The output format might be unexpected. $_", "Parsing Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
})
$form.Controls.Add($getSessionsButton)

# Create a label and textbox for the search input
$searchLabel = New-Object System.Windows.Forms.Label
$searchLabel.Text = "Search Usernames/Sessions:"
$searchLabel.Location = New-Object System.Drawing.Point(10, 90) # Position adjusted
$searchLabel.AutoSize = $true
$form.Controls.Add($searchLabel)

$searchTextBox = New-Object System.Windows.Forms.TextBox
$searchTextBox.Location = New-Object System.Drawing.Point(10, 110) # Position adjusted
$searchTextBox.Width = 200
$form.Controls.Add($searchTextBox)

# Create a button to trigger the search
$searchButton = New-Object System.Windows.Forms.Button
$searchButton.Text = "Search"
$searchButton.Location = New-Object System.Drawing.Point(220, 110) # Position adjusted
$searchButton.Width = 60 # Optional: Set a specific width
$searchButton.Add_Click({
    # Store all items temporarily
    $allItems = @()
    foreach ($item in $sessionsListBox.Items) {
        $allItems += $item
    }

    $searchText = $searchTextBox.Text.Trim()

    # Clear the listbox
    $sessionsListBox.Items.Clear()

    # If search text is empty, re-add all items
    if ([string]::IsNullOrWhiteSpace($searchText)) {
        $sessionsListBox.Items.AddRange($allItems)
        return
    }

    # Filter items based on search text
    $filteredItems = $allItems | Where-Object { $_ -like "*$searchText*" }

    # Add the filtered items back to the listbox
    if ($filteredItems.Count -gt 0) {
        $sessionsListBox.Items.AddRange($filteredItems)
    } else {
         # Optional: Show message or leave list empty
         # [System.Windows.Forms.MessageBox]::Show("No sessions found matching '$searchText'.", "Search", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    }
})
$form.Controls.Add($searchButton)

# Create a listbox to display the sessions
$sessionsListBox = New-Object System.Windows.Forms.ListBox
$sessionsListBox.Location = New-Object System.Drawing.Point(10, 140) # Position adjusted
$sessionsListBox.Width = 360
$sessionsListBox.Height = 160
$form.Controls.Add($sessionsListBox)

# Create a button to shadow the selected session
$shadowButton = New-Object System.Windows.Forms.Button
$shadowButton.Text = "Connect"
$shadowButton.Location = New-Object System.Drawing.Point(10, 310) # Position adjusted
$shadowButton.Width = 100 # Optional: Set a specific width
$shadowButton.Add_Click({
    if ($sessionsListBox.SelectedItem -ne $null) {
        $selectedSession = $sessionsListBox.SelectedItem
        # Split the display string to get username and ID
        # Expected format: "USERNAME - ID" or "SESSIONNAME - ID"
        $parts = $selectedSession -split " - "
        if ($parts.Count -ge 2) {
            # $username = $parts[0].Trim() # Username or Session Name
            $id = $parts[-1].Trim()       # ID is usually the last part

            # Use the selected server from the ComboBox for connection
            $SelectedServer = $serverComboBox.SelectedItem

            # Validate ID is numeric
            if (-not ($id -match "^\d+$")) {
                [System.Windows.Forms.MessageBox]::Show("Unable to determine session ID from selection '$selectedSession'.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                return
            }

            $commandArgs = @(
                "/v:$SelectedServer", # Use selected server
                "/shadow:$id",
                "/noConsentPrompt",
                "/control"
            )
            try {
                Start-Process -FilePath "mstsc.exe" -ArgumentList $commandArgs -NoNewWindow -ErrorAction Stop
            } catch {
                 [System.Windows.Forms.MessageBox]::Show("Failed to start mstsc.exe. Error: $_", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            }
        } else {
             [System.Windows.Forms.MessageBox]::Show("Unable to parse session information from selection '$selectedSession'.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    } else {
        [System.Windows.Forms.MessageBox]::Show("Please select a session to shadow.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
    }
})
$form.Controls.Add($shadowButton)

# Show the form
$form.Add_Shown({ $form.Activate() })
$result = $form.ShowDialog()

# Optional: Clean up resources
$form.Dispose()
