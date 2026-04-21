import Foundation
import IdentityLookup
import os.log

// ============================================================
// Live Caller ID Lookup Handler — 辅助类型定义
// ============================================================
//
// 此文件包含 Live Caller ID 扩展的辅助类型。
// 核心入口类 LiveCallerIDExtension 定义在 LiveCallerIDExtension.swift 中，
// 它同时实现 LiveCallerIDLookupProtocol 和 ILCallCommunicationCenterDelegate。
//
// 架构说明：
// - 默认：本地前缀匹配（ILCallCommunicationCenterDelegate）
// - 可选升级：PIR 服务器查询（LiveCallerIDLookupProtocol）
// - 两种方式在同一个 Extension 中共存，互不冲突
// ============================================================

// 此文件保留用于未来扩展，例如：
// - 自定义前缀规则的热更新逻辑
// - PIR 查询结果的本地缓存
// - 与主 App 的 App Group 数据同步

// 当前所有核心逻辑已整合到 LiveCallerIDExtension.swift
