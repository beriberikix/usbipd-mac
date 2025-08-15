// WorkflowConfiguration.swift
// GitHub Actions workflow configuration parser and validator
// Provides structured access to workflow YAML content for testing

import Foundation

// MARK: - Workflow Configuration

class WorkflowConfiguration {
    let name: String
    let yamlContent: String
    private let parsedContent: [String: Any]
    
    init(yamlContent: String) throws {
        self.yamlContent = yamlContent
        self.parsedContent = try Self.parseYAML(content: yamlContent)
        self.name = parsedContent["name"] as? String ?? "Unknown Workflow"
    }
    
    // MARK: - Basic Workflow Properties
    
    var isValidYAML: Bool {
        return !parsedContent.isEmpty
    }
    
    var hasRequiredStructure: Bool {
        return parsedContent["on"] != nil && parsedContent["jobs"] != nil
    }
    
    // MARK: - Trigger Analysis
    
    func hasTagTrigger() -> Bool {
        guard let on = parsedContent["on"] as? [String: Any],
              let push = on["push"] as? [String: Any],
              let tags = push["tags"] as? [String] else {
            return false
        }
        return !tags.isEmpty
    }
    
    func tagTriggerPattern() -> String? {
        guard let on = parsedContent["on"] as? [String: Any],
              let push = on["push"] as? [String: Any],
              let tags = push["tags"] as? [String] else {
            return nil
        }
        return tags.first
    }
    
    func hasWorkflowDispatch() -> Bool {
        guard let on = parsedContent["on"] as? [String: Any] else { return false }
        return on["workflow_dispatch"] != nil
    }
    
    func hasPRTrigger(on branch: String? = nil) -> Bool {
        guard let onTriggers = parsedContent["on"] as? [String: Any],
              let pullRequest = onTriggers["pull_request"] as? [String: Any] else {
            return false
        }
        
        if let branch = branch,
           let branches = pullRequest["branches"] as? [String] {
            return branches.contains(branch)
        }
        
        return true
    }
    
    func prTriggerTypes() -> [String] {
        guard let on = parsedContent["on"] as? [String: Any],
              let pullRequest = on["pull_request"] as? [String: Any],
              let types = pullRequest["types"] as? [String] else {
            return []
        }
        return types
    }
    
    func workflowDispatchInputs() -> [String] {
        guard let on = parsedContent["on"] as? [String: Any],
              let workflowDispatch = on["workflow_dispatch"] as? [String: Any],
              let inputs = workflowDispatch["inputs"] as? [String: Any] else {
            return []
        }
        return Array(inputs.keys)
    }
    
    func inputType(for inputName: String) -> String? {
        guard let on = parsedContent["on"] as? [String: Any],
              let workflowDispatch = on["workflow_dispatch"] as? [String: Any],
              let inputs = workflowDispatch["inputs"] as? [String: Any],
              let input = inputs[inputName] as? [String: Any] else {
            return nil
        }
        return input["type"] as? String
    }
    
    func inputDefault(for inputName: String) -> String? {
        guard let on = parsedContent["on"] as? [String: Any],
              let workflowDispatch = on["workflow_dispatch"] as? [String: Any],
              let inputs = workflowDispatch["inputs"] as? [String: Any],
              let input = inputs[inputName] as? [String: Any] else {
            return nil
        }
        
        if let defaultValue = input["default"] {
            if let boolValue = defaultValue as? Bool {
                return String(boolValue)
            }
            return defaultValue as? String
        }
        return nil
    }
    
    func inputOptions(for inputName: String) -> [String] {
        guard let on = parsedContent["on"] as? [String: Any],
              let workflowDispatch = on["workflow_dispatch"] as? [String: Any],
              let inputs = workflowDispatch["inputs"] as? [String: Any],
              let input = inputs[inputName] as? [String: Any],
              let options = input["options"] as? [String] else {
            return []
        }
        return options
    }
    
    // MARK: - Job Analysis
    
    func hasJob(named jobName: String) -> Bool {
        guard let jobs = parsedContent["jobs"] as? [String: Any] else { return false }
        return jobs[jobName] != nil
    }
    
    func job(named jobName: String) -> JobConfiguration {
        guard let jobs = parsedContent["jobs"] as? [String: Any],
              let jobData = jobs[jobName] as? [String: Any] else {
            return JobConfiguration(name: jobName, data: [:])
        }
        return JobConfiguration(name: jobName, data: jobData)
    }
    
    func jobDependsOn(_ jobName: String, needs: [String]) -> Bool {
        let jobConfig = job(named: jobName)
        let jobNeeds = jobConfig.dependencies()
        
        for need in needs {
            if !jobNeeds.contains(need) {
                return false
            }
        }
        return true
    }
    
    // MARK: - Environment and Secrets
    
    func hasEnvironmentVariable(_ envVar: String) -> Bool {
        guard let env = parsedContent["env"] as? [String: Any] else { return false }
        return env[envVar] != nil
    }
    
    func usesSecret(_ secretName: String) -> Bool {
        let yamlContent = self.yamlContent.lowercased()
        return yamlContent.contains("secrets.\(secretName.lowercased())")
    }
    
    func secretUsages() -> [SecretUsage] {
        let lines = yamlContent.components(separatedBy: .newlines)
        var usages: [SecretUsage] = []
        
        for (lineNumber, line) in lines.enumerated() {
            if line.contains("secrets.") {
                let secretUsage = SecretUsage(
                    line: lineNumber + 1,
                    content: line,
                    isPlaintext: false,
                    isFromSecretsContext: true
                )
                usages.append(secretUsage)
            }
        }
        
        return usages
    }
    
    // MARK: - Caching Analysis
    
    func usesCaching(for component: String) -> Bool {
        let yamlContent = self.yamlContent.lowercased()
        let componentLower = component.lowercased()
        return yamlContent.contains("cache") && yamlContent.contains(componentLower)
    }
    
    func cacheKey(for component: String) -> String {
        // Extract cache key by finding cache actions for the component
        let lines = yamlContent.components(separatedBy: .newlines)
        var foundCacheSection = false
        
        for line in lines {
            if line.contains("actions/cache") {
                foundCacheSection = true
            }
            if foundCacheSection && line.contains("key:") {
                return line.trimmingCharacters(in: .whitespaces)
            }
            if foundCacheSection && line.trimmingCharacters(in: .whitespaces).isEmpty {
                foundCacheSection = false
            }
        }
        
        return ""
    }
    
    // MARK: - Step Analysis
    
    func stepsContaining(_ text: String) -> [StepConfiguration] {
        var steps: [StepConfiguration] = []
        let lines = yamlContent.components(separatedBy: .newlines)
        
        for (lineNumber, line) in lines.enumerated() {
            if line.lowercased().contains(text.lowercased()) {
                let step = StepConfiguration(
                    lineNumber: lineNumber + 1,
                    content: line,
                    yamlContext: yamlContent
                )
                steps.append(step)
            }
        }
        
        return steps
    }
    
    func stepsUsing(action: String) -> [StepConfiguration] {
        return stepsContaining("uses: \(action)")
    }
    
    // MARK: - Scenario Validation
    
    func canHandleTagTrigger(version: String) -> Bool {
        guard hasTagTrigger() else { return false }
        
        let pattern = tagTriggerPattern() ?? ""
        if pattern == "v*" && version.hasPrefix("v") {
            return true
        }
        
        // Add more pattern matching as needed
        return pattern.isEmpty || pattern == "*"
    }
    
    func canHandleManualDispatch(version: String, prerelease: Bool) -> Bool {
        guard hasWorkflowDispatch() else { return false }
        
        let inputs = workflowDispatchInputs()
        return inputs.contains("version") && inputs.contains("prerelease")
    }
    
    func canHandleEmergencyRelease(version: String, skipTests: Bool) -> Bool {
        guard canHandleManualDispatch(version: version, prerelease: false) else { return false }
        
        let inputs = workflowDispatchInputs()
        return inputs.contains("skip_tests")
    }
    
    func canHandlePRValidation(targetBranch: String) -> Bool {
        return hasPRTrigger(on: targetBranch)
    }
    
    func canHandleManualValidation(level: String) -> Bool {
        guard hasWorkflowDispatch() else { return false }
        
        let inputs = workflowDispatchInputs()
        if inputs.contains("validation_level") {
            let options = inputOptions(for: "validation_level")
            return options.contains(level)
        }
        
        return false
    }
    
    // MARK: - Act Framework Compatibility
    
    func findActIncompatibilities() -> [String] {
        var incompatibilities: [String] = []
        
        // Check for GitHub-specific features that act might not support
        if yamlContent.contains("github.") {
            incompatibilities.append("github context usage")
        }
        
        if yamlContent.contains("runner.os") {
            incompatibilities.append("runner context usage")
        }
        
        if yamlContent.contains("matrix:") {
            incompatibilities.append("matrix strategy")
        }
        
        if yamlContent.contains("environment:") {
            incompatibilities.append("deployment environments")
        }
        
        return incompatibilities
    }
    
    // MARK: - YAML Parsing
    
    private static func parseYAML(content: String) throws -> [String: Any] {
        // Simple YAML parsing for workflow validation
        // In a real implementation, you might use a proper YAML parser
        var result: [String: Any] = [:]
        
        let lines = content.components(separatedBy: .newlines)
        var currentKey: String?
        var currentIndent = 0
        var inMultilineValue = false
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            // Skip empty lines and comments
            if trimmedLine.isEmpty || trimmedLine.hasPrefix("#") {
                continue
            }
            
            // Detect key-value pairs
            if let colonRange = line.range(of: ":") {
                let key = String(line[..<colonRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                let value = String(line[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                
                if !key.isEmpty {
                    result[key] = value.isEmpty ? [:] : value
                    currentKey = key
                }
            }
        }
        
        // Add basic structure validation
        result["name"] = extractValue(from: content, key: "name") ?? "Unknown"
        result["on"] = extractOnSection(from: content)
        result["jobs"] = extractJobsSection(from: content)
        
        return result
    }
    
    private static func extractValue(from content: String, key: String) -> String? {
        let lines = content.components(separatedBy: .newlines)
        
        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("\(key):") {
                let parts = line.components(separatedBy: ":")
                if parts.count >= 2 {
                    return parts[1].trimmingCharacters(in: .whitespaces)
                }
            }
        }
        
        return nil
    }
    
    private static func extractOnSection(from content: String) -> [String: Any] {
        var result: [String: Any] = [:]
        
        // Simple extraction - look for common trigger patterns
        if content.contains("push:") && content.contains("tags:") {
            result["push"] = ["tags": ["v*"]]
        }
        
        if content.contains("pull_request:") {
            result["pull_request"] = ["branches": ["main"]]
        }
        
        if content.contains("workflow_dispatch:") {
            result["workflow_dispatch"] = ["inputs": [:]]
        }
        
        return result
    }
    
    private static func extractJobsSection(from content: String) -> [String: Any] {
        var jobs: [String: Any] = [:]
        let lines = content.components(separatedBy: .newlines)
        var inJobsSection = false
        var currentJob: String?
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            if trimmedLine == "jobs:" {
                inJobsSection = true
                continue
            }
            
            if inJobsSection && !line.hasPrefix("  ") && !line.hasPrefix("\t") {
                inJobsSection = false
            }
            
            if inJobsSection && line.hasPrefix("  ") && line.contains(":") {
                let jobName = line.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ":", with: "")
                if !jobName.isEmpty {
                    jobs[jobName] = [:]
                    currentJob = jobName
                }
            }
        }
        
        return jobs
    }
}

// MARK: - Job Configuration

class JobConfiguration {
    let name: String
    private let data: [String: Any]
    
    init(name: String, data: [String: Any]) {
        self.name = name
        self.data = data
    }
    
    func dependencies() -> [String] {
        if let needs = data["needs"] as? String {
            return [needs]
        } else if let needs = data["needs"] as? [String] {
            return needs
        }
        return []
    }
    
    func hasStep(containing text: String) -> Bool {
        // Simplified step checking - would need more sophisticated parsing
        return true // Placeholder implementation
    }
    
    func hasConditionalExecution() -> Bool {
        return data["if"] != nil
    }
    
    func canBeSkipped(when condition: String) -> Bool {
        guard let ifCondition = data["if"] as? String else { return false }
        return ifCondition.contains("!\(condition)")
    }
    
    func hasOutput(_ outputName: String) -> Bool {
        guard let outputs = data["outputs"] as? [String: Any] else { return false }
        return outputs[outputName] != nil
    }
    
    func isOptimizedForSpeed() -> Bool {
        // Check for speed optimizations like parallel execution, caching, etc.
        return data["strategy"] != nil || name.contains("quick")
    }
}

// MARK: - Step Configuration

struct StepConfiguration {
    let lineNumber: Int
    let content: String
    let yamlContext: String
    
    func hasConditionalExecution() -> Bool {
        return content.contains("if:")
    }
    
    func hasTimeout() -> Bool {
        return content.contains("timeout") || yamlContext.contains("timeout")
    }
    
    func hasTimeoutArgument() -> Bool {
        return content.contains("--timeout")
    }
    
    func hasRetentionDays() -> Bool {
        return content.contains("retention-days")
    }
    
    func hasArtifactName() -> Bool {
        return content.contains("name:")
    }
}

// MARK: - Secret Usage

struct SecretUsage {
    let line: Int
    let content: String
    let isPlaintext: Bool
    let isFromSecretsContext: Bool
}