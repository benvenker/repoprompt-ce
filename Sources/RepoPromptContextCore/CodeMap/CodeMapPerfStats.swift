//
//  CodeMapPerfStats.swift
//  RepoPrompt
//
//  Lightweight counters for codemap performance analysis.
//  These are expected to be used on a single thread per file scan.
//

import Foundation

public struct CodeMapPerfOptions {
    public let enabled: Bool
    public let signposts: Bool
    public let collectCounters: Bool

    public static let disabled = CodeMapPerfOptions(enabled: false, signposts: false, collectCounters: false)
    public static let countersOnly = CodeMapPerfOptions(enabled: true, signposts: false, collectCounters: true)
    public static let full = CodeMapPerfOptions(enabled: true, signposts: true, collectCounters: true)
}

public struct CodeMapSyntaxStartupPerfStats {
    public var primeDuration: TimeInterval = 0
    public var warmCacheDuration: TimeInterval = 0
    public var warmCodeMapQueriesDuration: TimeInterval = 0
    public var languageConfigCreateDuration: TimeInterval = 0
    public var languagePointerDuration: TimeInterval = 0
    public var highlightQueryDataDuration: TimeInterval = 0
    public var highlightQueryCompileDuration: TimeInterval = 0
    public var codeMapQueryDataDuration: TimeInterval = 0
    public var codeMapQueryCompileDuration: TimeInterval = 0

    public var warmCacheLanguageCount = 0
    public var languageConfigCreateCount = 0
    public var languageConfigSuccessCount = 0
    public var languageConfigFailureCount = 0
    public var highlightQueryCompileSuccessCount = 0
    public var highlightQueryCompileFailureCount = 0
    public var warmCodeMapQueryLanguageCount = 0
    public var codeMapQueryPrecomputeSuccessCount = 0
    public var codeMapQueryPrecomputeFailureCount = 0
    public var codeMapQueryPrecomputeSkippedCount = 0
}

public struct CodeMapSyntaxPerfStats {
    public var languageLookupDuration: TimeInterval = 0
    public var oversizeGuardDuration: TimeInterval = 0
    public var parserCreateDuration: TimeInterval = 0
    public var setLanguageDuration: TimeInterval = 0
    public var parseDuration: TimeInterval = 0
    public var codeMapQueryLookupDuration: TimeInterval = 0
    public var queryExecuteDuration: TimeInterval = 0
    public var captureMaterializationDuration: TimeInterval = 0

    public var calls = 0
    public var unsupported = 0
    public var oversized = 0
    public var parseNilTree = 0
    public var parseNilRoot = 0
    public var parserCreates = 0
    public var queryExecutes = 0
    public var captures = 0
    public var codeMapQueryCacheHits = 0
    public var codeMapQueryCacheMisses = 0
}

public struct CodeMapPipelinePerfSnapshot: Equatable {
    public var snapshotBuildDuration: TimeInterval = 0
    public var requestBuildDuration: TimeInterval = 0
    public var contentLoadDuration: TimeInterval = 0
    public var actorRequestIngestDuration: TimeInterval = 0
    public var actorCachePrefetchDuration: TimeInterval = 0
    public var actorCacheCheckDuration: TimeInterval = 0
    public var actorQueueWaitDuration: TimeInterval = 0
    public var parseAndQueryDuration: TimeInterval = 0
    public var generatorDuration: TimeInterval = 0
    public var batchApplyDuration: TimeInterval = 0
    public var syntaxManagerPrimeDuration: TimeInterval = 0
    public var syntaxWarmCacheDuration: TimeInterval = 0
    public var syntaxWarmCodeMapQueriesDuration: TimeInterval = 0
    public var syntaxLanguageConfigCreateDuration: TimeInterval = 0
    public var syntaxLanguagePointerDuration: TimeInterval = 0
    public var syntaxHighlightQueryDataDuration: TimeInterval = 0
    public var syntaxHighlightQueryCompileDuration: TimeInterval = 0
    public var syntaxCodeMapQueryDataDuration: TimeInterval = 0
    public var syntaxCodeMapQueryCompileDuration: TimeInterval = 0
    public var syntaxLanguageLookupDuration: TimeInterval = 0
    public var syntaxOversizeGuardDuration: TimeInterval = 0
    public var syntaxParserCreateDuration: TimeInterval = 0
    public var syntaxSetLanguageDuration: TimeInterval = 0
    public var syntaxParseDuration: TimeInterval = 0
    public var syntaxCodeMapQueryLookupDuration: TimeInterval = 0
    public var syntaxQueryExecuteDuration: TimeInterval = 0
    public var syntaxCaptureMaterializationDuration: TimeInterval = 0
    public var generatorCaptureIndexDuration: TimeInterval = 0
    public var generatorSwiftContextDuration: TimeInterval = 0
    public var generatorTSContextDuration: TimeInterval = 0
    public var generatorCaptureLoopDuration: TimeInterval = 0
    public var generatorCaptureLoopLineAdvanceDuration: TimeInterval = 0
    public var generatorCaptureLoopSwiftStrategyDuration: TimeInterval = 0
    public var generatorCaptureLoopTSStrategyDuration: TimeInterval = 0
    public var generatorCaptureLoopInterfaceHeuristicDuration: TimeInterval = 0
    public var generatorCaptureLoopImportExportDuration: TimeInterval = 0
    public var generatorCaptureLoopTypeAliasDuration: TimeInterval = 0
    public var generatorCaptureLoopEnumMacroDuration: TimeInterval = 0
    public var generatorCaptureLoopFunctionDuration: TimeInterval = 0
    public var generatorCaptureLoopVariableDuration: TimeInterval = 0
    public var generatorCaptureLoopSkippedDuration: TimeInterval = 0
    public var generatorCaptureLoopUnclassifiedDuration: TimeInterval = 0
    public var generatorSwiftStrategyFunctionSignatureDuration: TimeInterval = 0
    public var generatorSwiftStrategyFunctionNameLookupDuration: TimeInterval = 0
    public var generatorSwiftStrategyParameterExtractionDuration: TimeInterval = 0
    public var generatorSwiftStrategyReturnTypeExtractionDuration: TimeInterval = 0
    public var generatorSwiftStrategyPropertyDeclarationDuration: TimeInterval = 0
    public var generatorSwiftStrategyPropertyTypeExtractionDuration: TimeInterval = 0
    public var generatorSwiftStrategyEnclosingTypeLookupDuration: TimeInterval = 0
    public var generatorSwiftStrategyModelInsertionDuration: TimeInterval = 0
    public var generatorSwiftStrategyContextOnlyDuration: TimeInterval = 0
    public var generatorFallbackFunctionDeclarationDuration: TimeInterval = 0
    public var generatorFallbackFunctionJSTSSignatureDuration: TimeInterval = 0
    public var generatorFallbackFunctionNameExtractionDuration: TimeInterval = 0
    public var generatorFallbackFunctionLTEParseDuration: TimeInterval = 0
    public var generatorFallbackFunctionTSFastPathDuration: TimeInterval = 0
    public var generatorFallbackFunctionReferencedTypesDuration: TimeInterval = 0
    public var generatorFallbackFunctionRoutingDuration: TimeInterval = 0
    public var generatorFallbackFunctionModelInsertionDuration: TimeInterval = 0
    public var generatorFallbackFunctionSkippedDuration: TimeInterval = 0
    public var generatorDeclarationExtractionDuration: TimeInterval = 0
    public var generatorJSTSSignatureDuration: TimeInterval = 0
    public var generatorLanguageTypeExtractorFunctionDuration: TimeInterval = 0
    public var generatorLanguageTypeExtractorVariableDuration: TimeInterval = 0
    public var generatorTypeCleanerDuration: TimeInterval = 0
    public var generatorTypeCleanerSwiftDuration: TimeInterval = 0
    public var generatorTypeCleanerTSDuration: TimeInterval = 0
    public var generatorTypeCleanerTSXDuration: TimeInterval = 0
    public var generatorTypeCleanerJSDuration: TimeInterval = 0
    public var generatorTypeCleanerOtherLanguageDuration: TimeInterval = 0
    public var generatorTypeCleanerPrecleanDuration: TimeInterval = 0
    public var generatorTypeCleanerTSLogicDuration: TimeInterval = 0
    public var generatorTypeCleanerNonTSLogicDuration: TimeInterval = 0
    public var generatorTypeCleanerTSObjectLiteralDuration: TimeInterval = 0
    public var generatorTypeCleanerFilterDuration: TimeInterval = 0
    public var generatorTypeCleanerDedupDuration: TimeInterval = 0
    public var generatorReferencedTypesFinalizeDuration: TimeInterval = 0
    public var generatorFileAPIInitDuration: TimeInterval = 0

    public var requestsBuilt = 0
    public var requestsEnqueued = 0
    public var cacheHits = 0
    public var cacheMisses = 0
    public var oversizedSkips = 0
    public var parseFailures = 0
    public var generatedAPIs = 0
    public var nilAPIs = 0
    public var codeMapQueryCacheHits = 0
    public var codeMapQueryCacheMisses = 0
    public var syntaxWarmCacheLanguageCount = 0
    public var syntaxLanguageConfigCreateCount = 0
    public var syntaxLanguageConfigSuccessCount = 0
    public var syntaxLanguageConfigFailureCount = 0
    public var syntaxHighlightQueryCompileSuccessCount = 0
    public var syntaxHighlightQueryCompileFailureCount = 0
    public var syntaxWarmCodeMapQueryLanguageCount = 0
    public var syntaxCodeMapQueryPrecomputeSuccessCount = 0
    public var syntaxCodeMapQueryPrecomputeFailureCount = 0
    public var syntaxCodeMapQueryPrecomputeSkippedCount = 0
    public var syntaxCodeMapCalls = 0
    public var syntaxUnsupportedExtensionCount = 0
    public var syntaxOversizedSkipCount = 0
    public var syntaxParseNilTreeCount = 0
    public var syntaxParseNilRootCount = 0
    public var syntaxParserCreateCount = 0
    public var syntaxQueryExecuteCount = 0
    public var syntaxCaptureCount = 0
    public var capturesProcessed = 0
    public var swiftStrategyHandled = 0
    public var tsStrategyHandled = 0
    public var fallbackHandled = 0
    public var generatorCaptureLoopLineAdvanceCount = 0
    public var generatorCaptureLoopSwiftStrategyCount = 0
    public var generatorCaptureLoopTSStrategyCount = 0
    public var generatorCaptureLoopInterfaceHeuristicCount = 0
    public var generatorCaptureLoopImportExportCount = 0
    public var generatorCaptureLoopTypeAliasCount = 0
    public var generatorCaptureLoopEnumMacroCount = 0
    public var generatorCaptureLoopFunctionCount = 0
    public var generatorCaptureLoopVariableCount = 0
    public var generatorCaptureLoopSkippedCount = 0
    public var generatorCaptureLoopUnclassifiedCount = 0
    public var generatorSwiftStrategyFunctionSignatureCount = 0
    public var generatorSwiftStrategyFunctionNameLookupCount = 0
    public var generatorSwiftStrategyParameterExtractionCount = 0
    public var generatorSwiftStrategyReturnTypeExtractionCount = 0
    public var generatorSwiftStrategyPropertyDeclarationCount = 0
    public var generatorSwiftStrategyPropertyTypeExtractionCount = 0
    public var generatorSwiftStrategyEnclosingTypeLookupCount = 0
    public var generatorSwiftStrategyModelInsertionCount = 0
    public var generatorSwiftStrategyContextOnlyCount = 0
    public var generatorSwiftStrategyHandledFunctionCount = 0
    public var generatorSwiftStrategyHandledPropertyCount = 0
    public var generatorFallbackFunctionDeclarationCount = 0
    public var generatorFallbackFunctionJSTSSignatureCount = 0
    public var generatorFallbackFunctionNameExtractionCount = 0
    public var generatorFallbackFunctionLTEParseCount = 0
    public var generatorFallbackFunctionTSFastPathCount = 0
    public var generatorFallbackFunctionReferencedTypesCount = 0
    public var generatorFallbackFunctionRoutingCount = 0
    public var generatorFallbackFunctionModelInsertionCount = 0
    public var generatorFallbackFunctionSkippedCount = 0
    public var generatorFallbackFunctionLightweightCount = 0
    public var generatorFallbackFunctionHeavyweightCount = 0
    public var generatorFallbackFunctionGlobalInsertCount = 0
    public var generatorFallbackFunctionMethodInsertCount = 0
    public var generatorFallbackFunctionInterfaceInsertCount = 0
    public var captureDeclarationCalls = 0
    public var jstsSignatureCallsFunctionLike = 0
    public var jstsSignatureCallsStatementLike = 0
    public var lteMatchAnyFunctionCalls = 0
    public var lteMatchAnyVariableCalls = 0
    public var typeCleanerExtractCalls = 0
    public var typeCleanerCacheHits = 0
    public var typeCleanerCacheMisses = 0
    public var typeCleanerSwiftCalls = 0
    public var typeCleanerTSCalls = 0
    public var typeCleanerTSXCalls = 0
    public var typeCleanerJSCalls = 0
    public var typeCleanerOtherLanguageCalls = 0
    public var typeCleanerPrecleanCount = 0
    public var typeCleanerTSLogicCount = 0
    public var typeCleanerNonTSLogicCount = 0
    public var typeCleanerTSObjectLiteralCount = 0
    public var typeCleanerFilterCount = 0
    public var typeCleanerDedupCount = 0
    public var referencedTypesRawInsertions = 0
    public var referencedTypesPrefilterSkips = 0
    public var referencedTypesEmptyResults = 0
    public var referencedTypesOutputTypeCount = 0
    public var extractionMemoJSTSHits = 0
    public var extractionMemoJSTSMisses = 0
    public var extractionMemoFunctionHits = 0
    public var extractionMemoFunctionMisses = 0
    public var extractionMemoFunctionParsedHits = 0
    public var extractionMemoFunctionParsedMisses = 0
    public var extractionMemoVariableHits = 0
    public var extractionMemoVariableMisses = 0
    public var extractionMemoTSFastPathHits = 0
    public var extractionMemoTSFastPathMisses = 0

    public var resultBatchCount = 0
    public var maxResultBatchSize = 0
}

public final class CodeMapPipelinePerfStats: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = CodeMapPipelinePerfSnapshot()

    public var snapshot: CodeMapPipelinePerfSnapshot {
        lock.withLock { storage }
    }

    public func addDuration(_ keyPath: WritableKeyPath<CodeMapPipelinePerfSnapshot, TimeInterval>, _ duration: TimeInterval) {
        lock.withLock {
            storage[keyPath: keyPath] += duration
        }
    }

    public func increment(_ keyPath: WritableKeyPath<CodeMapPipelinePerfSnapshot, Int>, by amount: Int = 1) {
        guard amount != 0 else { return }
        lock.withLock {
            storage[keyPath: keyPath] += amount
        }
    }

    public func recordResultBatch(size: Int) {
        lock.withLock {
            storage.resultBatchCount += 1
            storage.maxResultBatchSize = max(storage.maxResultBatchSize, size)
        }
    }

    public func mergeSyntaxManagerStartupStats(_ stats: CodeMapSyntaxStartupPerfStats) {
        lock.withLock {
            storage.syntaxManagerPrimeDuration += stats.primeDuration
            storage.syntaxWarmCacheDuration += stats.warmCacheDuration
            storage.syntaxWarmCodeMapQueriesDuration += stats.warmCodeMapQueriesDuration
            storage.syntaxLanguageConfigCreateDuration += stats.languageConfigCreateDuration
            storage.syntaxLanguagePointerDuration += stats.languagePointerDuration
            storage.syntaxHighlightQueryDataDuration += stats.highlightQueryDataDuration
            storage.syntaxHighlightQueryCompileDuration += stats.highlightQueryCompileDuration
            storage.syntaxCodeMapQueryDataDuration += stats.codeMapQueryDataDuration
            storage.syntaxCodeMapQueryCompileDuration += stats.codeMapQueryCompileDuration

            storage.syntaxWarmCacheLanguageCount += stats.warmCacheLanguageCount
            storage.syntaxLanguageConfigCreateCount += stats.languageConfigCreateCount
            storage.syntaxLanguageConfigSuccessCount += stats.languageConfigSuccessCount
            storage.syntaxLanguageConfigFailureCount += stats.languageConfigFailureCount
            storage.syntaxHighlightQueryCompileSuccessCount += stats.highlightQueryCompileSuccessCount
            storage.syntaxHighlightQueryCompileFailureCount += stats.highlightQueryCompileFailureCount
            storage.syntaxWarmCodeMapQueryLanguageCount += stats.warmCodeMapQueryLanguageCount
            storage.syntaxCodeMapQueryPrecomputeSuccessCount += stats.codeMapQueryPrecomputeSuccessCount
            storage.syntaxCodeMapQueryPrecomputeFailureCount += stats.codeMapQueryPrecomputeFailureCount
            storage.syntaxCodeMapQueryPrecomputeSkippedCount += stats.codeMapQueryPrecomputeSkippedCount
        }
    }

    public func mergeSyntaxCodeMapStats(_ stats: CodeMapSyntaxPerfStats) {
        lock.withLock {
            storage.syntaxLanguageLookupDuration += stats.languageLookupDuration
            storage.syntaxOversizeGuardDuration += stats.oversizeGuardDuration
            storage.syntaxParserCreateDuration += stats.parserCreateDuration
            storage.syntaxSetLanguageDuration += stats.setLanguageDuration
            storage.syntaxParseDuration += stats.parseDuration
            storage.syntaxCodeMapQueryLookupDuration += stats.codeMapQueryLookupDuration
            storage.syntaxQueryExecuteDuration += stats.queryExecuteDuration
            storage.syntaxCaptureMaterializationDuration += stats.captureMaterializationDuration

            storage.syntaxCodeMapCalls += stats.calls
            storage.syntaxUnsupportedExtensionCount += stats.unsupported
            storage.syntaxOversizedSkipCount += stats.oversized
            storage.syntaxParseNilTreeCount += stats.parseNilTree
            storage.syntaxParseNilRootCount += stats.parseNilRoot
            storage.syntaxParserCreateCount += stats.parserCreates
            storage.syntaxQueryExecuteCount += stats.queryExecutes
            storage.syntaxCaptureCount += stats.captures
            storage.codeMapQueryCacheHits += stats.codeMapQueryCacheHits
            storage.codeMapQueryCacheMisses += stats.codeMapQueryCacheMisses
        }
    }

    public func mergeGeneratorStats(_ stats: CodeMapPerfStats) {
        lock.withLock {
            storage.generatorCaptureIndexDuration += stats.captureIndexDuration
            storage.generatorSwiftContextDuration += stats.swiftContextDuration
            storage.generatorTSContextDuration += stats.tsContextDuration
            storage.generatorCaptureLoopDuration += stats.captureLoopDuration
            storage.generatorCaptureLoopLineAdvanceDuration += stats.captureLoopLineAdvanceDuration
            storage.generatorCaptureLoopSwiftStrategyDuration += stats.captureLoopSwiftStrategyDuration
            storage.generatorCaptureLoopTSStrategyDuration += stats.captureLoopTSStrategyDuration
            storage.generatorCaptureLoopInterfaceHeuristicDuration += stats.captureLoopInterfaceHeuristicDuration
            storage.generatorCaptureLoopImportExportDuration += stats.captureLoopImportExportDuration
            storage.generatorCaptureLoopTypeAliasDuration += stats.captureLoopTypeAliasDuration
            storage.generatorCaptureLoopEnumMacroDuration += stats.captureLoopEnumMacroDuration
            storage.generatorCaptureLoopFunctionDuration += stats.captureLoopFunctionDuration
            storage.generatorCaptureLoopVariableDuration += stats.captureLoopVariableDuration
            storage.generatorCaptureLoopSkippedDuration += stats.captureLoopSkippedDuration
            storage.generatorCaptureLoopUnclassifiedDuration += stats.captureLoopUnclassifiedDuration
            storage.generatorSwiftStrategyFunctionSignatureDuration += stats.swiftStrategyFunctionSignatureDuration
            storage.generatorSwiftStrategyFunctionNameLookupDuration += stats.swiftStrategyFunctionNameLookupDuration
            storage.generatorSwiftStrategyParameterExtractionDuration += stats.swiftStrategyParameterExtractionDuration
            storage.generatorSwiftStrategyReturnTypeExtractionDuration += stats.swiftStrategyReturnTypeExtractionDuration
            storage.generatorSwiftStrategyPropertyDeclarationDuration += stats.swiftStrategyPropertyDeclarationDuration
            storage.generatorSwiftStrategyPropertyTypeExtractionDuration += stats.swiftStrategyPropertyTypeExtractionDuration
            storage.generatorSwiftStrategyEnclosingTypeLookupDuration += stats.swiftStrategyEnclosingTypeLookupDuration
            storage.generatorSwiftStrategyModelInsertionDuration += stats.swiftStrategyModelInsertionDuration
            storage.generatorSwiftStrategyContextOnlyDuration += stats.swiftStrategyContextOnlyDuration
            storage.generatorFallbackFunctionDeclarationDuration += stats.fallbackFunctionDeclarationDuration
            storage.generatorFallbackFunctionJSTSSignatureDuration += stats.fallbackFunctionJSTSSignatureDuration
            storage.generatorFallbackFunctionNameExtractionDuration += stats.fallbackFunctionNameExtractionDuration
            storage.generatorFallbackFunctionLTEParseDuration += stats.fallbackFunctionLTEParseDuration
            storage.generatorFallbackFunctionTSFastPathDuration += stats.fallbackFunctionTSFastPathDuration
            storage.generatorFallbackFunctionReferencedTypesDuration += stats.fallbackFunctionReferencedTypesDuration
            storage.generatorFallbackFunctionRoutingDuration += stats.fallbackFunctionRoutingDuration
            storage.generatorFallbackFunctionModelInsertionDuration += stats.fallbackFunctionModelInsertionDuration
            storage.generatorFallbackFunctionSkippedDuration += stats.fallbackFunctionSkippedDuration
            storage.generatorDeclarationExtractionDuration += stats.captureDeclarationDuration
            storage.generatorJSTSSignatureDuration += stats.jstsSignatureDuration
            storage.generatorLanguageTypeExtractorFunctionDuration += stats.languageTypeExtractorFunctionDuration
            storage.generatorLanguageTypeExtractorVariableDuration += stats.languageTypeExtractorVariableDuration
            storage.generatorTypeCleanerDuration += stats.typeCleanerDuration
            storage.generatorTypeCleanerSwiftDuration += stats.typeCleanerSwiftDuration
            storage.generatorTypeCleanerTSDuration += stats.typeCleanerTSDuration
            storage.generatorTypeCleanerTSXDuration += stats.typeCleanerTSXDuration
            storage.generatorTypeCleanerJSDuration += stats.typeCleanerJSDuration
            storage.generatorTypeCleanerOtherLanguageDuration += stats.typeCleanerOtherLanguageDuration
            storage.generatorTypeCleanerPrecleanDuration += stats.typeCleanerPrecleanDuration
            storage.generatorTypeCleanerTSLogicDuration += stats.typeCleanerTSLogicDuration
            storage.generatorTypeCleanerNonTSLogicDuration += stats.typeCleanerNonTSLogicDuration
            storage.generatorTypeCleanerTSObjectLiteralDuration += stats.typeCleanerTSObjectLiteralDuration
            storage.generatorTypeCleanerFilterDuration += stats.typeCleanerFilterDuration
            storage.generatorTypeCleanerDedupDuration += stats.typeCleanerDedupDuration
            storage.generatorReferencedTypesFinalizeDuration += stats.referencedTypesFinalizeDuration
            storage.generatorFileAPIInitDuration += stats.fileAPIInitDuration

            storage.capturesProcessed += stats.capturesProcessed
            storage.swiftStrategyHandled += stats.swiftStrategyHandled
            storage.tsStrategyHandled += stats.tsStrategyHandled
            storage.fallbackHandled += stats.fallbackHandled
            storage.generatorCaptureLoopLineAdvanceCount += stats.captureLoopLineAdvanceCount
            storage.generatorCaptureLoopSwiftStrategyCount += stats.captureLoopSwiftStrategyCount
            storage.generatorCaptureLoopTSStrategyCount += stats.captureLoopTSStrategyCount
            storage.generatorCaptureLoopInterfaceHeuristicCount += stats.captureLoopInterfaceHeuristicCount
            storage.generatorCaptureLoopImportExportCount += stats.captureLoopImportExportCount
            storage.generatorCaptureLoopTypeAliasCount += stats.captureLoopTypeAliasCount
            storage.generatorCaptureLoopEnumMacroCount += stats.captureLoopEnumMacroCount
            storage.generatorCaptureLoopFunctionCount += stats.captureLoopFunctionCount
            storage.generatorCaptureLoopVariableCount += stats.captureLoopVariableCount
            storage.generatorCaptureLoopSkippedCount += stats.captureLoopSkippedCount
            storage.generatorCaptureLoopUnclassifiedCount += stats.captureLoopUnclassifiedCount
            storage.generatorSwiftStrategyFunctionSignatureCount += stats.swiftStrategyFunctionSignatureCount
            storage.generatorSwiftStrategyFunctionNameLookupCount += stats.swiftStrategyFunctionNameLookupCount
            storage.generatorSwiftStrategyParameterExtractionCount += stats.swiftStrategyParameterExtractionCount
            storage.generatorSwiftStrategyReturnTypeExtractionCount += stats.swiftStrategyReturnTypeExtractionCount
            storage.generatorSwiftStrategyPropertyDeclarationCount += stats.swiftStrategyPropertyDeclarationCount
            storage.generatorSwiftStrategyPropertyTypeExtractionCount += stats.swiftStrategyPropertyTypeExtractionCount
            storage.generatorSwiftStrategyEnclosingTypeLookupCount += stats.swiftStrategyEnclosingTypeLookupCount
            storage.generatorSwiftStrategyModelInsertionCount += stats.swiftStrategyModelInsertionCount
            storage.generatorSwiftStrategyContextOnlyCount += stats.swiftStrategyContextOnlyCount
            storage.generatorSwiftStrategyHandledFunctionCount += stats.swiftStrategyHandledFunctionCount
            storage.generatorSwiftStrategyHandledPropertyCount += stats.swiftStrategyHandledPropertyCount
            storage.generatorFallbackFunctionDeclarationCount += stats.fallbackFunctionDeclarationCount
            storage.generatorFallbackFunctionJSTSSignatureCount += stats.fallbackFunctionJSTSSignatureCount
            storage.generatorFallbackFunctionNameExtractionCount += stats.fallbackFunctionNameExtractionCount
            storage.generatorFallbackFunctionLTEParseCount += stats.fallbackFunctionLTEParseCount
            storage.generatorFallbackFunctionTSFastPathCount += stats.fallbackFunctionTSFastPathCount
            storage.generatorFallbackFunctionReferencedTypesCount += stats.fallbackFunctionReferencedTypesCount
            storage.generatorFallbackFunctionRoutingCount += stats.fallbackFunctionRoutingCount
            storage.generatorFallbackFunctionModelInsertionCount += stats.fallbackFunctionModelInsertionCount
            storage.generatorFallbackFunctionSkippedCount += stats.fallbackFunctionSkippedCount
            storage.generatorFallbackFunctionLightweightCount += stats.fallbackFunctionLightweightCount
            storage.generatorFallbackFunctionHeavyweightCount += stats.fallbackFunctionHeavyweightCount
            storage.generatorFallbackFunctionGlobalInsertCount += stats.fallbackFunctionGlobalInsertCount
            storage.generatorFallbackFunctionMethodInsertCount += stats.fallbackFunctionMethodInsertCount
            storage.generatorFallbackFunctionInterfaceInsertCount += stats.fallbackFunctionInterfaceInsertCount
            storage.captureDeclarationCalls += stats.captureDeclarationCalls
            storage.jstsSignatureCallsFunctionLike += stats.jstsSignatureCallsFunctionLike
            storage.jstsSignatureCallsStatementLike += stats.jstsSignatureCallsStatementLike
            storage.lteMatchAnyFunctionCalls += stats.lteMatchAnyFunctionCalls
            storage.lteMatchAnyVariableCalls += stats.lteMatchAnyVariableCalls
            storage.typeCleanerExtractCalls += stats.typeCleanerExtractCalls
            storage.typeCleanerCacheHits += stats.typeCleanerCacheHits
            storage.typeCleanerCacheMisses += stats.typeCleanerCacheMisses
            storage.typeCleanerSwiftCalls += stats.typeCleanerSwiftCalls
            storage.typeCleanerTSCalls += stats.typeCleanerTSCalls
            storage.typeCleanerTSXCalls += stats.typeCleanerTSXCalls
            storage.typeCleanerJSCalls += stats.typeCleanerJSCalls
            storage.typeCleanerOtherLanguageCalls += stats.typeCleanerOtherLanguageCalls
            storage.typeCleanerPrecleanCount += stats.typeCleanerPrecleanCount
            storage.typeCleanerTSLogicCount += stats.typeCleanerTSLogicCount
            storage.typeCleanerNonTSLogicCount += stats.typeCleanerNonTSLogicCount
            storage.typeCleanerTSObjectLiteralCount += stats.typeCleanerTSObjectLiteralCount
            storage.typeCleanerFilterCount += stats.typeCleanerFilterCount
            storage.typeCleanerDedupCount += stats.typeCleanerDedupCount
            storage.referencedTypesRawInsertions += stats.referencedTypesRawInsertions
            storage.referencedTypesPrefilterSkips += stats.referencedTypesPrefilterSkips
            storage.referencedTypesEmptyResults += stats.referencedTypesEmptyResults
            storage.referencedTypesOutputTypeCount += stats.referencedTypesOutputTypeCount
            storage.extractionMemoJSTSHits += stats.extractionMemoJSTSHits
            storage.extractionMemoJSTSMisses += stats.extractionMemoJSTSMisses
            storage.extractionMemoFunctionHits += stats.extractionMemoFunctionHits
            storage.extractionMemoFunctionMisses += stats.extractionMemoFunctionMisses
            storage.extractionMemoFunctionParsedHits += stats.extractionMemoFunctionParsedHits
            storage.extractionMemoFunctionParsedMisses += stats.extractionMemoFunctionParsedMisses
            storage.extractionMemoVariableHits += stats.extractionMemoVariableHits
            storage.extractionMemoVariableMisses += stats.extractionMemoVariableMisses
            storage.extractionMemoTSFastPathHits += stats.extractionMemoTSFastPathHits
            storage.extractionMemoTSFastPathMisses += stats.extractionMemoTSFastPathMisses
        }
    }
}

public enum CodeMapPerfRuntime {
    public static let instrumentationEnvironmentKey = "REPOPROMPT_CODEMAP_PERF"
    public static let benchmarkEnvironmentKey = "REPOPROMPT_RUN_CODEMAP_BENCHMARKS"
    public static let benchmarkIterationsEnvironmentKey = "REPOPROMPT_CODEMAP_BENCHMARK_ITERATIONS"
    public static let benchmarkMarkerPath = "/tmp/repoprompt-run-codemap-benchmarks"

    #if DEBUG || CODEMAP_PERF
        static let isCompiledIn = true
    #else
        static let isCompiledIn = false
    #endif

    private static var benchmarkMarkerEnabled: Bool {
        guard isCompiledIn else { return false }
        return !isRunningInCI && FileManager.default.fileExists(atPath: benchmarkMarkerPath)
    }

    private static var benchmarkRequested: Bool {
        guard isCompiledIn else { return false }
        return environmentFlagEnabled(benchmarkEnvironmentKey)
            || CommandLine.arguments.contains("--run-codemap-benchmarks")
            || benchmarkMarkerEnabled
    }

    public static let isEnabled: Bool = {
        guard isCompiledIn else { return false }
        return environmentFlagEnabled(instrumentationEnvironmentKey) || benchmarkRequested
    }()

    public static let sharedPipelineStats: CodeMapPipelinePerfStats? = isEnabled ? CodeMapPipelinePerfStats() : nil

    public static func makeGeneratorOptions() -> CodeMapPerfOptions {
        isEnabled ? .countersOnly : .disabled
    }

    public static func makeGeneratorStats() -> CodeMapPerfStats? {
        isEnabled ? CodeMapPerfStats() : nil
    }

    @inline(__always)
    public static func activeOptions(_ options: CodeMapPerfOptions) -> CodeMapPerfOptions {
        #if DEBUG || CODEMAP_PERF
            return options
        #else
            return .disabled
        #endif
    }

    @inline(__always)
    public static func activeStats(_ stats: CodeMapPerfStats?) -> CodeMapPerfStats? {
        #if DEBUG || CODEMAP_PERF
            return stats
        #else
            return nil
        #endif
    }

    public static var shouldRunBenchmarks: Bool {
        benchmarkRequested
    }

    public static var isRunningInCI: Bool {
        ["CI", "GITHUB_ACTIONS", "BUILDKITE", "JENKINS_URL", "TEAMCITY_VERSION"].contains { key in
            ProcessInfo.processInfo.environment[key] != nil
        }
    }

    public static func environmentFlagEnabled(_ name: String) -> Bool {
        guard let rawValue = ProcessInfo.processInfo.environment[name] else {
            return false
        }
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on", "enabled", "enable", "run":
            return true
        default:
            return false
        }
    }

    public static func currentTime() -> DispatchTime {
        DispatchTime.now()
    }

    public static func durationSince(_ start: DispatchTime) -> TimeInterval {
        Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000.0
    }
}

public final class CodeMapPerfStats {
    // Capture loop
    public var capturesProcessed = 0
    public var swiftStrategyHandled = 0
    public var tsStrategyHandled = 0
    public var fallbackHandled = 0
    public var captureLoopLineAdvanceCount = 0
    public var captureLoopSwiftStrategyCount = 0
    public var captureLoopTSStrategyCount = 0
    public var captureLoopInterfaceHeuristicCount = 0
    public var captureLoopImportExportCount = 0
    public var captureLoopTypeAliasCount = 0
    public var captureLoopEnumMacroCount = 0
    public var captureLoopFunctionCount = 0
    public var captureLoopVariableCount = 0
    public var captureLoopSkippedCount = 0
    public var captureLoopUnclassifiedCount = 0
    public var swiftStrategyFunctionSignatureCount = 0
    public var swiftStrategyFunctionNameLookupCount = 0
    public var swiftStrategyParameterExtractionCount = 0
    public var swiftStrategyReturnTypeExtractionCount = 0
    public var swiftStrategyPropertyDeclarationCount = 0
    public var swiftStrategyPropertyTypeExtractionCount = 0
    public var swiftStrategyEnclosingTypeLookupCount = 0
    public var swiftStrategyModelInsertionCount = 0
    public var swiftStrategyContextOnlyCount = 0
    public var swiftStrategyHandledFunctionCount = 0
    public var swiftStrategyHandledPropertyCount = 0
    public var fallbackFunctionDeclarationCount = 0
    public var fallbackFunctionJSTSSignatureCount = 0
    public var fallbackFunctionNameExtractionCount = 0
    public var fallbackFunctionLTEParseCount = 0
    public var fallbackFunctionTSFastPathCount = 0
    public var fallbackFunctionReferencedTypesCount = 0
    public var fallbackFunctionRoutingCount = 0
    public var fallbackFunctionModelInsertionCount = 0
    public var fallbackFunctionSkippedCount = 0
    public var fallbackFunctionLightweightCount = 0
    public var fallbackFunctionHeavyweightCount = 0
    public var fallbackFunctionGlobalInsertCount = 0
    public var fallbackFunctionMethodInsertCount = 0
    public var fallbackFunctionInterfaceInsertCount = 0

    // Declaration capture + JS/TS signature extraction
    public var captureDeclarationCalls = 0
    public var jstsSignatureCallsFunctionLike = 0
    public var jstsSignatureCallsStatementLike = 0

    // LanguageTypeExtractor
    public var lteMatchAnyFunctionCalls = 0
    public var lteMatchAnyVariableCalls = 0
    public var tsConstructorMatches = 0
    public var tsAccessorMatches = 0
    public var tsClassMethodMatches = 0
    public var tsClassArrowMatches = 0
    public var tsClassArrowNoParensMatches = 0
    public var tsArrowFunctionMatches = 0
    public var tsArrowFunctionParamsReturnMatches = 0
    public var tsxConstructorMatches = 0
    public var tsxAccessorMatches = 0
    public var tsxClassMethodMatches = 0
    public var tsxClassArrowMatches = 0
    public var tsxClassArrowNoParensMatches = 0
    public var tsxArrowFunctionMatches = 0
    public var tsxArrowFunctionParamsReturnMatches = 0
    public var swiftReturnTypeFastPathHits = 0
    public var tsReturnTypeFastPathHits = 0
    public var tsTypeAnnotationFastPathHits = 0
    public var tsTypeAliasRhsFastPathHits = 0

    // TypeCleaner
    public var typeCleanerExtractCalls = 0
    public var typeCleanerCacheHits = 0
    public var typeCleanerCacheMisses = 0
    public var typeCleanerSwiftCalls = 0
    public var typeCleanerTSCalls = 0
    public var typeCleanerTSXCalls = 0
    public var typeCleanerJSCalls = 0
    public var typeCleanerOtherLanguageCalls = 0
    public var typeCleanerPrecleanCount = 0
    public var typeCleanerTSLogicCount = 0
    public var typeCleanerNonTSLogicCount = 0
    public var typeCleanerTSObjectLiteralCount = 0
    public var typeCleanerFilterCount = 0
    public var typeCleanerDedupCount = 0
    public var referencedTypesRawInsertions = 0
    public var referencedTypesPrefilterSkips = 0
    public var referencedTypesEmptyResults = 0
    public var referencedTypesOutputTypeCount = 0

    // Extraction memo
    public var extractionMemoJSTSHits = 0
    public var extractionMemoJSTSMisses = 0
    public var extractionMemoFunctionHits = 0
    public var extractionMemoFunctionMisses = 0
    public var extractionMemoFunctionParsedHits = 0
    public var extractionMemoFunctionParsedMisses = 0
    public var extractionMemoVariableHits = 0
    public var extractionMemoVariableMisses = 0
    public var extractionMemoTSFastPathHits = 0
    public var extractionMemoTSFastPathMisses = 0

    // Durations
    public var captureIndexDuration: TimeInterval = 0
    public var swiftContextDuration: TimeInterval = 0
    public var tsContextDuration: TimeInterval = 0
    public var captureLoopDuration: TimeInterval = 0
    public var captureLoopLineAdvanceDuration: TimeInterval = 0
    public var captureLoopSwiftStrategyDuration: TimeInterval = 0
    public var captureLoopTSStrategyDuration: TimeInterval = 0
    public var captureLoopInterfaceHeuristicDuration: TimeInterval = 0
    public var captureLoopImportExportDuration: TimeInterval = 0
    public var captureLoopTypeAliasDuration: TimeInterval = 0
    public var captureLoopEnumMacroDuration: TimeInterval = 0
    public var captureLoopFunctionDuration: TimeInterval = 0
    public var captureLoopVariableDuration: TimeInterval = 0
    public var captureLoopSkippedDuration: TimeInterval = 0
    public var captureLoopUnclassifiedDuration: TimeInterval = 0
    public var swiftStrategyFunctionSignatureDuration: TimeInterval = 0
    public var swiftStrategyFunctionNameLookupDuration: TimeInterval = 0
    public var swiftStrategyParameterExtractionDuration: TimeInterval = 0
    public var swiftStrategyReturnTypeExtractionDuration: TimeInterval = 0
    public var swiftStrategyPropertyDeclarationDuration: TimeInterval = 0
    public var swiftStrategyPropertyTypeExtractionDuration: TimeInterval = 0
    public var swiftStrategyEnclosingTypeLookupDuration: TimeInterval = 0
    public var swiftStrategyModelInsertionDuration: TimeInterval = 0
    public var swiftStrategyContextOnlyDuration: TimeInterval = 0
    public var fallbackFunctionDeclarationDuration: TimeInterval = 0
    public var fallbackFunctionJSTSSignatureDuration: TimeInterval = 0
    public var fallbackFunctionNameExtractionDuration: TimeInterval = 0
    public var fallbackFunctionLTEParseDuration: TimeInterval = 0
    public var fallbackFunctionTSFastPathDuration: TimeInterval = 0
    public var fallbackFunctionReferencedTypesDuration: TimeInterval = 0
    public var fallbackFunctionRoutingDuration: TimeInterval = 0
    public var fallbackFunctionModelInsertionDuration: TimeInterval = 0
    public var fallbackFunctionSkippedDuration: TimeInterval = 0
    public var captureDeclarationDuration: TimeInterval = 0
    public var jstsSignatureDuration: TimeInterval = 0
    public var languageTypeExtractorFunctionDuration: TimeInterval = 0
    public var languageTypeExtractorVariableDuration: TimeInterval = 0
    public var typeCleanerDuration: TimeInterval = 0
    public var typeCleanerSwiftDuration: TimeInterval = 0
    public var typeCleanerTSDuration: TimeInterval = 0
    public var typeCleanerTSXDuration: TimeInterval = 0
    public var typeCleanerJSDuration: TimeInterval = 0
    public var typeCleanerOtherLanguageDuration: TimeInterval = 0
    public var typeCleanerPrecleanDuration: TimeInterval = 0
    public var typeCleanerTSLogicDuration: TimeInterval = 0
    public var typeCleanerNonTSLogicDuration: TimeInterval = 0
    public var typeCleanerTSObjectLiteralDuration: TimeInterval = 0
    public var typeCleanerFilterDuration: TimeInterval = 0
    public var typeCleanerDedupDuration: TimeInterval = 0
    public var referencedTypesFinalizeDuration: TimeInterval = 0
    public var fileAPIInitDuration: TimeInterval = 0
}
