import 'package:flutter/material.dart';
import '../models/customer.dart';
import '../services/database_service.dart';
import '../utils/constants.dart';

class CustomerSearchWidget extends StatefulWidget {
  final Function(Customer) onCustomerSelected;
  final Function(String) onNewCustomerName;
  final String? initialValue;
  final Future<List<Customer>> Function(String query)? search;

  const CustomerSearchWidget({
    super.key,
    required this.onCustomerSelected,
    required this.onNewCustomerName,
    this.initialValue,
    this.search,
  });

  @override
  State<CustomerSearchWidget> createState() => _CustomerSearchWidgetState();
}

class _CustomerSearchWidgetState extends State<CustomerSearchWidget> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  List<Customer> _suggestions = [];
  bool _showSuggestions = false;
  bool _isCustomerSelected = false;
  bool _loading = false;
  String? _searchError;
  int _searchRevision = 0;

  @override
  void initState() {
    super.initState();
    if (widget.initialValue != null) {
      _controller.text = widget.initialValue!;
    }
    _focusNode.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    if (!mounted) return;
    if (!_focusNode.hasFocus) {
      setState(() => _showSuggestions = false);
    } else if (!_isCustomerSelected && _controller.text.trim().isNotEmpty) {
      _search(_controller.text);
    }
  }

  @override
  void dispose() {
    ++_searchRevision;
    _focusNode.removeListener(_onFocusChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _onSearchChanged(String query) async {
    // Clear the parent's selection immediately, even when the field is empty.
    widget.onNewCustomerName(query);
    _isCustomerSelected = false;
    await _search(query);
  }

  Future<void> _search(String query) async {
    final revision = ++_searchRevision;
    if (query.trim().isEmpty) {
      setState(() {
        _suggestions = [];
        _showSuggestions = false;
        _loading = false;
        _searchError = null;
      });
      return;
    }
    setState(() {
      _suggestions = [];
      _showSuggestions = false;
      _loading = true;
      _searchError = null;
    });
    try {
      final search = widget.search ?? DatabaseService.instance.searchCustomers;
      final customers = await search(query);
      if (!mounted || revision != _searchRevision) return;
      setState(() {
        _suggestions = customers;
        _showSuggestions = _focusNode.hasFocus;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || revision != _searchRevision) return;
      setState(() {
        _loading = false;
        _showSuggestions = false;
        _searchError =
            'Müşteri araması yapılamadı. Mevcut müşteri için yeniden deneyin.';
      });
    }
  }

  void _retry() {
    if (_loading) return;
    if (!_focusNode.hasFocus) {
      _focusNode.requestFocus();
    } else {
      _search(_controller.text);
    }
  }

  void _selectCustomer(Customer customer) {
    ++_searchRevision;
    _controller.text = customer.name;
    setState(() {
      _showSuggestions = false;
      _isCustomerSelected = true;
      _loading = false;
      _searchError = null;
    });
    widget.onCustomerSelected(customer);
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search field
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _isCustomerSelected
                  ? AppColors.gold.withValues(alpha: 0.5)
                  : AppColors.divider,
            ),
          ),
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            onChanged: _onSearchChanged,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.none,
            style: const TextStyle(color: AppColors.white, fontSize: 16),
            decoration: InputDecoration(
              hintText: 'Lütfen müşteri adı belirleyin...',
              hintStyle: TextStyle(
                color: AppColors.textSecondary.withValues(alpha: 0.6),
              ),
              prefixIcon: Icon(
                _isCustomerSelected ? Icons.person : Icons.search,
                color: _isCustomerSelected
                    ? AppColors.gold
                    : AppColors.textSecondary,
              ),
              suffixIcon: _controller.text.isNotEmpty
                  ? IconButton(
                      tooltip: 'Müşteri seçimini temizle',
                      icon: const Icon(
                        Icons.clear,
                        color: AppColors.textSecondary,
                      ),
                      onPressed: () {
                        _controller.clear();
                        _onSearchChanged('');
                      },
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
          ),
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(),
                SizedBox(height: 4),
                Text('Müşteriler aranıyor…'),
              ],
            ),
          ),
        if (_searchError != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_searchError!),
                TextButton(
                  onPressed: _retry,
                  child: const Text('Aramayı yeniden dene'),
                ),
              ],
            ),
          ),
        // Suggestions dropdown
        if (_showSuggestions && _suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.divider),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: _suggestions.length,
              separatorBuilder: (context, index) =>
                  Divider(color: AppColors.divider, height: 1),
              itemBuilder: (context, index) {
                final customer = _suggestions[index];
                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    backgroundColor: AppColors.gold.withValues(alpha: 0.15),
                    radius: 18,
                    child: Text(
                      customer.name.isEmpty
                          ? '?'
                          : customer.name.characters.first.toUpperCase(),
                      style: const TextStyle(
                        color: AppColors.gold,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(
                    customer.name,
                    style: const TextStyle(
                      color: AppColors.white,
                      fontSize: 15,
                    ),
                  ),
                  subtitle:
                      customer.phone != null ||
                          customer.favoriteHairstyle != null
                      ? Text(
                          [
                            if (customer.phone != null &&
                                customer.phone!.isNotEmpty)
                              '📞 ${customer.phone}',
                            if (customer.favoriteHairstyle != null &&
                                customer.favoriteHairstyle!.isNotEmpty)
                              '✂️ ${customer.favoriteHairstyle}',
                          ].join('   '),
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        )
                      : null,
                  onTap: () => _selectCustomer(customer),
                );
              },
            ),
          ),
      ],
    );
  }
}
