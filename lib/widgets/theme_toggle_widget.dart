// lib/widgets/theme_toggle_widget.dart

import 'package:flutter/material.dart';
import '../providers/theme_provider.dart';

class ThemeToggleWidget extends StatelessWidget {
  final bool showLabel;
  
  const ThemeToggleWidget({
    super.key,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    final themeProvider = ThemeProvider();
    
    return AnimatedBuilder(
      animation: themeProvider,
      builder: (context, child) {
        final isDark = themeProvider.isDarkMode;
        
        if (showLabel) {
          // Versão com Label (para Sidebar)
          return ListTile(
            leading: Icon(
              isDark ? Icons.dark_mode : Icons.light_mode,
              color: Theme.of(context).iconTheme.color,
            ),
            title: Text(
              isDark ? 'Modo Escuro' : 'Modo Claro',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            trailing: Switch(
              value: isDark,
              onChanged: (value) => themeProvider.toggleTheme(),
              activeColor: Theme.of(context).colorScheme.primary,
            ),
          );
        } else {
          // Versão compacta (para AppBar)
          return IconButton(
            icon: Icon(
              isDark ? Icons.light_mode : Icons.dark_mode,
            ),
            tooltip: isDark ? 'Modo Claro' : 'Modo Escuro',
            onPressed: () => themeProvider.toggleTheme(),
          );
        }
      },
    );
  }
}

// Widget Switch apenas (para uso customizado)
class ThemeSwitch extends StatelessWidget {
  const ThemeSwitch({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = ThemeProvider();
    
    return AnimatedBuilder(
      animation: themeProvider,
      builder: (context, child) {
        return Switch(
          value: themeProvider.isDarkMode,
          onChanged: (value) => themeProvider.toggleTheme(),
          activeColor: Theme.of(context).colorScheme.primary,
        );
      },
    );
  }
}

// Widget com animação bonita
class AnimatedThemeToggle extends StatelessWidget {
  const AnimatedThemeToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = ThemeProvider();
    
    return AnimatedBuilder(
      animation: themeProvider,
      builder: (context, child) {
        final isDark = themeProvider.isDarkMode;
        
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(30),
              onTap: () => themeProvider.toggleTheme(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      transitionBuilder: (child, animation) {
                        return RotationTransition(
                          turns: animation,
                          child: child,
                        );
                      },
                      child: Icon(
                        isDark ? Icons.dark_mode : Icons.light_mode,
                        key: ValueKey(isDark),
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isDark ? 'Escuro' : 'Claro',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}