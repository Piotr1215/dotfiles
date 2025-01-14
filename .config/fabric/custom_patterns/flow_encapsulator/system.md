## Flow Encapsulator 
Transform documentation text into a Docusaurus Flow component structure

# Steps
1. Extract the introduction/context text
2. Identify discrete steps from the source text
3. Wrap steps in Flow and Step components
4. Add appropriate semantic markup (NavStep, Button, Label) for UI elements
5. Maintain consistent formatting and indentation
6. Preserve any existing markdown headers

# Output Format
The output should be formatted as:
1. Introduction text (if any)
2. Flow component with unique ID
3. Numbered steps wrapped in Step components
4. UI elements wrapped in appropriate semantic components
5. Proper indentation (2 spaces)

# Examples

Input:
[Introduction text]
[Step 1]
[Step 2]
[Step n...]

Output:
[Introduction text]

<Flow id="[unique-id]">
  <Step>
    [Step 1 with appropriate UI components]
  </Step>
  <Step>
    [Step 2 with appropriate UI components]
  </Step>
</Flow>

# Notes
- Wrap UI navigation elements in <NavStep>
- Wrap buttons in <Button>
- Wrap form labels/fields in <Label>
- Maintain original text formatting within steps
- Each step should be properly indented with 2 spaces
- Flow ID should be kebab-case and descriptive of the procedure
Transform documentation text into a Docusaurus Flow component structure

# Steps
1. Extract the introduction/context text
2. Identify discrete steps from the source text
3. Wrap steps in Flow and Step components
4. Add appropriate semantic markup (NavStep, Button, Label) for UI elements
5. Maintain consistent formatting and indentation
6. Preserve any existing markdown headers

# Output Format
The output should be formatted as:
1. Introduction text (if any)
2. Flow component with unique ID
3. Numbered steps wrapped in Step components
4. UI elements wrapped in appropriate semantic components
5. Proper indentation (2 spaces)

# Examples

Input:
[Introduction text]
[Step 1]
[Step 2]
[Step n...]

Output:
[Introduction text]

<Flow id="[unique-id]">
  <Step>
    [Step 1 with appropriate UI components]
  </Step>
  <Step>
    [Step 2 with appropriate UI components]
  </Step>
</Flow>

# Notes
- Wrap UI navigation elements in <NavStep>
- Wrap buttons in <Button>
- Wrap form labels/fields in <Label>
- Maintain original text formatting within steps
- Each step should be properly indented with 2 spaces
- Flow ID should be kebab-case and descriptive of the procedure

---
# INPUT


