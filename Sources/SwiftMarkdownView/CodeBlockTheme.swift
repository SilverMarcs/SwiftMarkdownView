//
//  CodeBlockTheme.swift
//  LynkChat
//
//  Created by Zabir Raihan on 28/12/2024.
//


public enum CodeBlockTheme: String, Codable, CaseIterable {
    case atom
    case github
    case a11y
    case panda
    case paraiso
    case stackoverflow
    case tokyo
    
    var fileName: String {
        switch self {
        case .atom:
            return "atom"
        case .github:
            return "github"
        case .a11y:
            return "a11y"
        case .panda:
            return "panda"
        case .paraiso:
            return "paraiso"
        case .stackoverflow:
            return "stackoverflow"
        case .tokyo:
            return "tokyo"
        }
    }
    
    public var name: String {
        switch self {
        case .atom:
            return "Atom One"
        case .github:
            return "GitHub"
        case .a11y:
            return "A11Y"
        case .panda:
            return "Panda"
        case .paraiso:
            return "Paraiso"
        case .stackoverflow:
            return "StackOverflow"
        case .tokyo:
            return "Tokyo"
        }
    }
}
