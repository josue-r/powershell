import csv
import json

# Initialize an empty list to store the results
sarif_results = []
rules = []

# Read the CSV file
with open('analysis-results-2.csv', mode='r') as file:
    csv_reader = csv.DictReader(file)
    for row in csv_reader:
        # Each row corresponds to one rule violation
        sarif_result = {
            "ruleId": row['RuleName'],
            "message": {
                "text": row['Message']
            },
            "locations": [
                {
                    "physicalLocation": {
                        "artifactLocation": {
                            "uri": row['ScriptName']
                        },
                        "region": {
                            "startLine": int(row['Line'])
                        }
                    }
                }
            ],
            "level": row['Severity'].lower()
        }
        sarif_results.append(sarif_result)
        
        # Adding rule information
        rule = {
            "id": row['RuleName'],
            "name": row['RuleName'],
            "shortDescription": {
                "text": f"Violation: {row['RuleName']}"
            },
            "fullDescription": {
                "text": "A detailed description of the rule violation."
            },
            "defaultConfiguration": {
                "level": row['Severity'].lower()
            }
        }
        rules.append(rule)

# Ensure there are results before generating the SARIF report
if sarif_results:
    sarif_report = {
        "version": "2.1.0",
        "runs": [
            {
                "tool": {
                    "driver": {
                        "name": "PSScriptAnalyzer",
                        "rules": rules
                    }
                },
                "results": sarif_results
            }
        ]
    }

    # Convert the SARIF report to JSON format
    sarif_json = json.dumps(sarif_report, indent=4)

    # Output the JSON to a file
    with open("result.sarif", "w") as sarif_file:
        sarif_file.write(sarif_json)

    print("SARIF report generated and saved to result.sarif")
else:
    print("No data found in CSV. SARIF report was not generated.")
