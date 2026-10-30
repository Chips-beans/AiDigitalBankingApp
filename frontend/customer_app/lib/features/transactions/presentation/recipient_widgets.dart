import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../app/design_system/design_system.dart';
import '../transfer_support.dart';

/// A receiver's profile photo, or their initial when they have none.
class RecipientAvatar extends StatelessWidget {
  const RecipientAvatar({
    required this.number,
    this.directory,
    this.size = 40,
    super.key,
  }) : name = null,
       bytes = null;
  const RecipientAvatar.fromBytes(
    String this.name,
    this.bytes, {
    this.size = 40,
    super.key,
  }) : number = null,
       directory = null;
  final String? number, name;
  final RecipientDirectory? directory;
  final Uint8List? bytes;
  final double size;

  @override
  Widget build(BuildContext context) {
    final directory = this.directory, number = this.number;
    if (directory == null || number == null) return _circle(context, name, bytes);
    return FutureBuilder<Recipient?>(
      future: directory.lookup(number),
      builder: (context, found) {
        final recipient = found.data;
        if (recipient?.hasPhoto != true) {
          return _circle(context, recipient?.name, null);
        }
        return FutureBuilder<Uint8List?>(
          future: directory.photo(number),
          builder: (context, photo) =>
              _circle(context, recipient!.name, photo.data),
        );
      },
    );
  }

  Widget _circle(BuildContext context, String? name, Uint8List? photo) {
    final initial = name?.trim().isNotEmpty == true
        ? name!.trim().characters.first.toUpperCase()
        : '#';
    return Semantics(
      excludeSemantics: true,
      child: Container(
        width: size,
        height: size,
        clipBehavior: Clip.antiAlias,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: AppPalette.navy500,
        ),
        alignment: Alignment.center,
        child: photo != null
            ? Image.memory(
                photo,
                width: size,
                height: size,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => _initial(initial),
              )
            : _initial(initial),
      ),
    );
  }

  Widget _initial(String initial) => Text(
    initial,
    style: TextStyle(
      color: AppPalette.gold500,
      fontSize: size * .42,
      fontWeight: FontWeight.w600,
    ),
  );
}

/// The receiver's profile name, falling back to the account number.
class RecipientName extends StatelessWidget {
  const RecipientName({required this.number, this.directory, super.key});
  final String number;
  final RecipientDirectory? directory;
  @override
  Widget build(BuildContext context) {
    final directory = this.directory;
    if (directory == null) return Text(number);
    return FutureBuilder<Recipient?>(
      future: directory.lookup(number),
      builder: (context, found) => Text(
        found.data?.name ?? number,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
