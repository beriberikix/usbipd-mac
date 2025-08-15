// WorkflowTestUtilities.swift
// Utilities and helpers for GitHub Actions workflow testing
// Provides common functionality for workflow validation and testing

import Foundation
import XCTest
@testable import USBIPDCore
@testable import USBIPDCLI
@testable import Common

// MARK: - Workflow Test Utilities

struct WorkflowTestUtilities {
    
    // MARK: - File System Utilities
    
    static func workflowExists(named filename: String) -> Bool {
        let workflowPath = ".github/workflows/\(filename)"
        return FileManager.default.fileExists(atPath: workflowPath)
    }
    
    static func loadWorkflowContent(filename: String) throws -> String {
        let workflowPath = ".github/workflows/\(filename)"
        
        guard FileManager.default.fileExists(atPath: workflowPath) else {
            throw WorkflowTestError.workflowNotFound(filename)
        }
        
        return try String(contentsOfFile: workflowPath, encoding: .utf8)
    }
    
    static func validateWorkflowYAMLSyntax(_ content: String) -> Bool {
        // Basic YAML syntax validation
        let lines = content.components(separatedBy: .newlines)
        var indentationStack: [Int] = []
        
        for (lineNumber, line) in lines.enumerated() {
            // Skip empty lines and comments
            if line.trimmingCharacters(in: .whitespaces).isEmpty || 
               line.trimmingCharacters(in: .whitespaces).hasPrefix("#") {
                continue
            }
            
            let indentation = countLeadingSpaces(in: line)
            
            // Validate indentation consistency
            if line.contains(":") && !line.trimmingCharacters(in: .whitespaces).hasPrefix("-") {
                // Key-value pair
                if let lastIndent = indentationStack.last {
                    if indentation > lastIndent && (indentation - lastIndent) % 2 != 0 {
                        print("⚠️ Inconsistent indentation at line \(lineNumber + 1): \(line)")
                        return false
                    }
                }
                
                if indentation > (indentationStack.last ?? -1) {
                    indentationStack.append(indentation)
                } else {
                    // Pop indentation levels
                    while let lastIndent = indentationStack.last, lastIndent >= indentation {
                        indentationStack.removeLast()
                    }
                    indentationStack.append(indentation)
                }
            }
        }
        
        return true
    }
    
    private static func countLeadingSpaces(in line: String) -> Int {
        var count = 0
        for character in line {
            if character == " " {
                count += 1
            } else {
                break
            }
        }
        return count
    }
    
    // MARK: - Workflow Structure Validation
    
    static func validateWorkflowStructure(_ content: String) throws -> WorkflowStructureReport {
        var report = WorkflowStructureReport()
        
        let lines = content.components(separatedBy: .newlines)
        var currentSection: String?
        var inJobsSection = false
        var currentJob: String?
        
        for (lineNumber, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            // Skip empty lines and comments
            if trimmedLine.isEmpty || trimmedLine.hasPrefix("#") {
                continue
            }
            
            // Identify main sections
            if line.hasPrefix("name:") {
                report.hasName = true
                report.name = extractValue(from: line)
            } else if line.hasPrefix("on:") {
                currentSection = "on"
                report.hasOnSection = true
            } else if line.hasPrefix("env:") {
                currentSection = "env"
                report.hasEnvSection = true
            } else if line.hasPrefix("jobs:") {
                currentSection = "jobs"
                inJobsSection = true
                report.hasJobsSection = true
            }
            
            // Parse triggers
            if currentSection == "on" {
                if trimmedLine.contains("push:") {
                    report.triggers.append("push")
                } else if trimmedLine.contains("pull_request:") {
                    report.triggers.append("pull_request")
                } else if trimmedLine.contains("workflow_dispatch:") {
                    report.triggers.append("workflow_dispatch")
                } else if trimmedLine.contains("schedule:") {
                    report.triggers.append("schedule")
                }
            }
            
            // Parse environment variables
            if currentSection == "env" && line.contains(":") {
                let envVar = extractKey(from: line)
                if !envVar.isEmpty {
                    report.environmentVariables.append(envVar)
                }
            }
            
            // Parse jobs
            if inJobsSection && line.hasPrefix("  ") && !line.hasPrefix("    ") && line.contains(":") {
                let jobName = extractKey(from: line)
                if !jobName.isEmpty {
                    report.jobs.append(jobName)
                    currentJob = jobName
                }
            }
            
            // Parse job properties
            if let job = currentJob, line.hasPrefix("    ") {
                if trimmedLine.hasPrefix("needs:") {
                    let dependencies = extractDependencies(from: line)
                    report.jobDependencies[job] = dependencies
                } else if trimmedLine.hasPrefix("if:") {
                    report.conditionalJobs.insert(job)
                } else if trimmedLine.hasPrefix("runs-on:") {
                    let runner = extractValue(from: line)
                    report.jobRunners[job] = runner
                }
            }
        }
        
        // Validate required sections
        report.isValid = report.hasName && report.hasOnSection && report.hasJobsSection && !report.jobs.isEmpty
        
        return report
    }
    
    private static func extractValue(from line: String) -> String {
        let components = line.components(separatedBy: ":")
        if components.count >= 2 {
            return components[1].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }
    
    private static func extractKey(from line: String) -> String {
        let components = line.components(separatedBy: ":")
        if components.count >= 1 {
            return components[0].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }
    
    private static func extractDependencies(from line: String) -> [String] {
        let value = extractValue(from: line)
        
        // Handle both single dependency and array format
        if value.hasPrefix("[") && value.hasSuffix("]") {
            // Array format: needs: [job1, job2]
            let cleaned = value.dropFirst().dropLast()
            return cleaned.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        } else {
            // Single dependency: needs: job1
            return value.isEmpty ? [] : [value]
        }
    }
    
    // MARK: - Security Validation
    
    static func scanForSecurityIssues(in content: String) -> [SecurityIssue] {
        var issues: [SecurityIssue] = []
        let lines = content.components(separatedBy: .newlines)
        
        for (lineNumber, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            // Check for hardcoded secrets
            let secretPatterns = [
                "password\\s*[:=]\\s*['\"][^'\"]+['\"]",
                "api[_-]?key\\s*[:=]\\s*['\"][^'\"]+['\"]",
                "token\\s*[:=]\\s*['\"][^'\"]+['\"]",
                "secret\\s*[:=]\\s*['\"][^'\"]+['\"]"
            ]
            
            for pattern in secretPatterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                   regex.firstMatch(in: line, range: NSRange(location: 0, length: line.count)) != nil {
                    issues.append(SecurityIssue(
                        type: .hardcodedSecret,
                        line: lineNumber + 1,
                        content: line,
                        description: "Potential hardcoded secret detected"
                    ))
                }
            }
            
            // Check for insecure action versions
            if trimmedLine.contains("uses:") && trimmedLine.contains("@") {
                let actionParts = trimmedLine.components(separatedBy: "@")
                if actionParts.count >= 2 {
                    let version = actionParts[1].trimmingCharacters(in: .whitespaces)
                    if version == "main" || version == "master" {
                        issues.append(SecurityIssue(
                            type: .insecureActionVersion,
                            line: lineNumber + 1,
                            content: line,
                            description: "Using mutable action version (\(version)) instead of specific version or SHA"
                        ))
                    }
                }
            }
            
            // Check for overly permissive permissions
            if trimmedLine.contains("permissions:") && line.contains("write-all") {
                issues.append(SecurityIssue(
                    type: .overlyPermissivePermissions,
                    line: lineNumber + 1,
                    content: line,
                    description: "Overly permissive permissions detected"
                ))
            }
            
            // Check for shell injection risks
            if (trimmedLine.contains("run:") || trimmedLine.contains("shell:")) && 
               line.contains("${{ github.event.") && 
               !line.contains("github.event.inputs.") {
                issues.append(SecurityIssue(
                    type: .shellInjectionRisk,
                    line: lineNumber + 1,
                    content: line,
                    description: "Potential shell injection from untrusted input"
                ))
            }
        }
        
        return issues
    }
    
    // MARK: - Performance Analysis
    
    static func analyzeWorkflowPerformance(content: String) -> PerformanceAnalysis {
        var analysis = PerformanceAnalysis()
        let lines = content.components(separatedBy: .newlines)
        
        var inJobsSection = false
        var currentJob: String?
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            if line.hasPrefix("jobs:") {
                inJobsSection = true
                continue
            }
            
            if inJobsSection && line.hasPrefix("  ") && !line.hasPrefix("    ") && line.contains(":") {
                currentJob = extractKey(from: line)
                continue
            }
            
            // Analyze caching
            if trimmedLine.contains("actions/cache") {
                analysis.usesCaching = true
                analysis.cachingActions += 1
            }
            
            // Analyze parallelism
            if trimmedLine.contains("strategy:") || trimmedLine.contains("matrix:") {
                analysis.usesMatrixStrategy = true
            }
            
            // Analyze job dependencies
            if trimmedLine.hasPrefix("needs:") {
                analysis.jobDependencies += 1
            }
            
            // Check for time-intensive operations
            let timeIntensivePatterns = [
                "swift build",
                "swift test",
                "swiftlint",
                "xcodebuild"
            ]
            
            for pattern in timeIntensivePatterns {
                if line.lowercased().contains(pattern) {
                    analysis.timeIntensiveOperations += 1
                }
            }
            
            // Check for optimization opportunities
            if trimmedLine.contains("brew install") && !line.contains("cache") {
                analysis.optimizationOpportunities.append("Consider caching brew installations")
            }
            
            if trimmedLine.contains("swift build") && !analysis.usesCaching {
                analysis.optimizationOpportunities.append("Consider caching Swift build artifacts")
            }
        }
        
        // Calculate performance score (0-100)
        var score = 100
        score -= analysis.timeIntensiveOperations * 5 // Deduct for each time-intensive operation
        score += analysis.usesCaching ? 15 : 0 // Bonus for caching
        score += analysis.usesMatrixStrategy ? 10 : 0 // Bonus for parallelism
        score -= analysis.jobDependencies * 2 // Slight deduction for dependencies (can limit parallelism)
        
        analysis.performanceScore = max(0, min(100, score))
        
        return analysis
    }
    
    // MARK: - Test Helpers
    
    static func createTemporaryWorkflowFile(content: String) throws -> URL {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("workflow-tests-\(UUID().uuidString)")
        
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let workflowFile = tempDir.appendingPathComponent("test-workflow.yml")
        try content.write(to: workflowFile, atomically: true, encoding: .utf8)
        
        return workflowFile
    }
    
    static func cleanupTemporaryFiles(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - Supporting Types

struct WorkflowStructureReport {
    var isValid = false
    var hasName = false
    var hasOnSection = false
    var hasEnvSection = false
    var hasJobsSection = false
    
    var name = ""
    var triggers: [String] = []
    var environmentVariables: [String] = []
    var jobs: [String] = []
    var conditionalJobs: Set<String> = []
    var jobDependencies: [String: [String]] = [:]
    var jobRunners: [String: String] = [:]
    
    var summary: String {
        return """
        Workflow Structure Report:
        • Valid: \(isValid)
        • Name: \(name.isEmpty ? "Not specified" : name)
        • Triggers: \(triggers.joined(separator: ", "))
        • Jobs: \(jobs.count) (\(jobs.joined(separator: ", ")))
        • Conditional Jobs: \(conditionalJobs.count)
        • Environment Variables: \(environmentVariables.count)
        """
    }
}

struct SecurityIssue {
    let type: SecurityIssueType
    let line: Int
    let content: String
    let description: String
    
    var severity: SecuritySeverity {
        switch type {
        case .hardcodedSecret:
            return .high
        case .shellInjectionRisk:
            return .high
        case .overlyPermissivePermissions:
            return .medium
        case .insecureActionVersion:
            return .low
        }
    }
}

enum SecurityIssueType {
    case hardcodedSecret
    case shellInjectionRisk
    case overlyPermissivePermissions
    case insecureActionVersion
}

enum SecuritySeverity {
    case low
    case medium
    case high
}

struct PerformanceAnalysis {
    var performanceScore = 0
    var usesCaching = false
    var usesMatrixStrategy = false
    var cachingActions = 0
    var jobDependencies = 0
    var timeIntensiveOperations = 0
    var optimizationOpportunities: [String] = []
    
    var summary: String {
        return """
        Performance Analysis:
        • Score: \(performanceScore)/100
        • Uses Caching: \(usesCaching)
        • Uses Matrix Strategy: \(usesMatrixStrategy)
        • Time-Intensive Operations: \(timeIntensiveOperations)
        • Optimization Opportunities: \(optimizationOpportunities.count)
        """
    }
}

enum WorkflowTestError: Error, LocalizedError {
    case workflowNotFound(String)
    case invalidYAMLSyntax(String)
    case missingRequiredSection(String)
    case invalidJobConfiguration(String)
    
    var errorDescription: String? {
        switch self {
        case .workflowNotFound(let filename):
            return "Workflow file not found: \(filename)"
        case .invalidYAMLSyntax(let details):
            return "Invalid YAML syntax: \(details)"
        case .missingRequiredSection(let section):
            return "Missing required section: \(section)"
        case .invalidJobConfiguration(let job):
            return "Invalid job configuration: \(job)"
        }
    }
}

// MARK: - Test Assertions Extensions

extension XCTestCase {
    
    func assertWorkflowExists(_ filename: String, file: StaticString = #file, line: UInt = #line) {
        XCTAssertTrue(WorkflowTestUtilities.workflowExists(named: filename),
                     "Workflow file \(filename) should exist",
                     file: file, line: line)
    }
    
    func assertWorkflowHasValidStructure(_ content: String, file: StaticString = #file, line: UInt = #line) throws {
        let report = try WorkflowTestUtilities.validateWorkflowStructure(content)
        XCTAssertTrue(report.isValid, 
                     "Workflow should have valid structure. Report: \(report.summary)",
                     file: file, line: line)
    }
    
    func assertWorkflowHasNoSecurityIssues(_ content: String, allowedSeverities: Set<SecuritySeverity> = [.low], file: StaticString = #file, line: UInt = #line) {
        let issues = WorkflowTestUtilities.scanForSecurityIssues(in: content)
        let criticalIssues = issues.filter { !allowedSeverities.contains($0.severity) }
        
        XCTAssertTrue(criticalIssues.isEmpty,
                     "Workflow should have no critical security issues. Found: \(criticalIssues.map { $0.description })",
                     file: file, line: line)
    }
    
    func assertWorkflowPerformanceScore(_ content: String, minimumScore: Int, file: StaticString = #file, line: UInt = #line) {
        let analysis = WorkflowTestUtilities.analyzeWorkflowPerformance(content: content)
        XCTAssertGreaterThanOrEqual(analysis.performanceScore, minimumScore,
                                   "Workflow performance score should be at least \(minimumScore). Analysis: \(analysis.summary)",
                                   file: file, line: line)
    }
}